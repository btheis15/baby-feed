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

    /// Cancel whatever is pending and schedule from the latest feed.
    static func reschedule(lastFeed: FeedEntry?, unit: VolumeUnit, babyName: String) async {
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: [requestID])

        guard AppSettings.remindersEnabled, let lastFeed else {
            await FeedAlarmScheduler.cancelPending()
            return
        }

        let due = AppSettings.nextDue(after: lastFeed.startTime)
        let lastText = "\(lastFeed.kind.title) · \(lastFeed.detailText(unit: unit)) at \(lastFeed.startTime.formatted(date: .omitted, time: .shortened))"

        if AppSettings.useAlarm {
            // A real alarm: rings through silent mode and Focus.
            await FeedAlarmScheduler.schedule(at: due, babyName: babyName)
        } else {
            await FeedAlarmScheduler.cancelPending()
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

        let components = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute, .second], from: date)
        let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
        let request = UNNotificationRequest(identifier: requestID, content: content, trigger: trigger)
        try? await UNUserNotificationCenter.current().add(request)
    }

    static func snooze(minutes: Int = 15) async {
        let date = Date.now.addingTimeInterval(Double(minutes) * 60)
        await schedule(at: date, title: "Time for a feed", body: "Snoozed reminder.")
    }
}
