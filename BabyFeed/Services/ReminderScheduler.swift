import Foundation
import UserNotifications

/// Schedules the "next feed" notification. When the caregiver prefers a real
/// alarm, hands off to `FeedAlarmScheduler` instead.
@MainActor
enum ReminderScheduler {
    static let requestID = "babyfeed.nextFeed"
    static let categoryID = "NEXT_FEED"
    static let logAction = "LOG_FEED"
    static let snoozeAction = "SNOOZE_15"

    static func registerCategories() {
        let log = UNNotificationAction(identifier: logAction, title: "Log a feed", options: [.foreground])
        let snooze = UNNotificationAction(identifier: snoozeAction, title: "Remind me in 15 min", options: [])
        let category = UNNotificationCategory(identifier: categoryID, actions: [log, snooze], intentIdentifiers: [], options: [])
        UNUserNotificationCenter.current().setNotificationCategories([category])
    }

    static func requestAuthorization() async -> Bool {
        do {
            return try await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge])
        } catch {
            return false
        }
    }

    // A snooze has to outlive the app being opened. Every foreground
    // reschedules, and the reschedule used to remove the snoozed
    // notification and not put it back, because the due time had passed.
    private static let snoozedUntilKey = "reminders.snoozedUntil"
    /// The feed the snoozed reminder was about; a newer feed makes it moot.
    private static let snoozedFeedKey = "reminders.snoozedFeedStart"
    private static let scheduledFeedKey = "reminders.scheduledFeedStart"

    /// Whether a snooze still stands: it's in the future, and nobody has
    /// logged a feed since it was set.
    nonisolated static func keepsSnooze(snoozedUntil: Date?, snoozedForFeedAt: Date?, lastFeedStart: Date?, now: Date) -> Bool {
        guard let snoozedUntil, snoozedUntil > now,
              let snoozedForFeedAt, let lastFeedStart else { return false }
        return lastFeedStart.timeIntervalSince(snoozedForFeedAt) < 1
    }

    private static func storedDate(_ key: String) -> Date? {
        let seconds = UserDefaults.standard.double(forKey: key)
        return seconds > 0 ? Date(timeIntervalSince1970: seconds) : nil
    }

    private static func clearSnooze() {
        UserDefaults.standard.removeObject(forKey: snoozedUntilKey)
        UserDefaults.standard.removeObject(forKey: snoozedFeedKey)
    }

    /// Cancel whatever is pending and schedule from the latest feed.
    static func reschedule(lastFeed: FeedEntry?, unit: VolumeUnit, babyName: String) async {
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: [requestID])

        guard AppSettings.remindersEnabled, let lastFeed else {
            clearSnooze()
            await FeedAlarmScheduler.cancelPending()
            return
        }
        UserDefaults.standard.set(lastFeed.startTime.timeIntervalSince1970, forKey: scheduledFeedKey)

        let due = AppSettings.nextDue(after: lastFeed.startTime)
        let lastText = "\(lastFeed.kind.title) · \(lastFeed.detailText(unit: unit)) at \(ClockText.time(lastFeed.startTime, in: AppSettings.timeZone))"

        if AppSettings.useAlarm {
            // A real alarm: rings through silent mode and Focus.
            clearSnooze()
            await FeedAlarmScheduler.schedule(at: due, babyName: babyName)
        } else {
            await FeedAlarmScheduler.cancelPending()
            if keepsSnooze(snoozedUntil: storedDate(snoozedUntilKey),
                           snoozedForFeedAt: storedDate(snoozedFeedKey),
                           lastFeedStart: lastFeed.startTime,
                           now: .now),
               let until = storedDate(snoozedUntilKey) {
                await schedule(at: until, title: "Time for a feed", body: "Snoozed reminder.")
                return
            }
            clearSnooze()
            guard due > .now else { return }
            await schedule(at: due, title: "Time to feed \(babyName)", body: "Last feed: \(lastText)")
        }
    }

    static func schedule(at date: Date, title: String, body: String) async {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        content.categoryIdentifier = categoryID
        content.interruptionLevel = .timeSensitive

        let components = AppSettings.calendar.dateComponents([.year, .month, .day, .hour, .minute, .second], from: date)
        let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
        let request = UNNotificationRequest(identifier: requestID, content: content, trigger: trigger)
        try? await UNUserNotificationCenter.current().add(request)
    }

    static func snooze(minutes: Int = 15) async {
        let date = Date.now.addingTimeInterval(Double(minutes) * 60)
        UserDefaults.standard.set(date.timeIntervalSince1970, forKey: snoozedUntilKey)
        UserDefaults.standard.set(UserDefaults.standard.double(forKey: scheduledFeedKey), forKey: snoozedFeedKey)
        await schedule(at: date, title: "Time for a feed", body: "Snoozed reminder.")
    }
}
