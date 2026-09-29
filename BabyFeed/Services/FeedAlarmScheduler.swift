import AlarmKit
import Foundation
import SwiftUI

/// Metadata attached to the alarm. Nothing to carry yet.
struct FeedAlarmMetadata: AlarmMetadata {}

/// One-shot AlarmKit alarm for the next feed. Unlike a notification it rings
/// in silent mode and through Focus, and shows the system alarm UI.
/// Alert-only alarms do not need a Live Activity, so no widget code is involved.
@MainActor
enum FeedAlarmScheduler {
    private static let idKey = "reminders.alarmID"

    static func requestAuthorization() async -> Bool {
        do {
            return try await AlarmManager.shared.requestAuthorization() == .authorized
        } catch {
            return false
        }
    }

    static func cancelPending() async {
        UserDefaults.standard.removeObject(forKey: dateKey)
        guard let raw = UserDefaults.standard.string(forKey: idKey), let id = UUID(uuidString: raw) else { return }
        try? AlarmManager.shared.cancel(id: id)
        UserDefaults.standard.removeObject(forKey: idKey)
    }

    /// When the alarm we set is for, so asking again for the same time is a no-op.
    private static let dateKey = "reminders.alarmDate"

    static func schedule(at date: Date, babyName: String) async {
        // Already set for exactly this time: leave it. Every foreground and
        // every sync used to cancel it, ask for permission again and re-create it.
        if UserDefaults.standard.string(forKey: idKey) != nil,
           abs(UserDefaults.standard.double(forKey: dateKey) - date.timeIntervalSince1970) < 1 {
            return
        }
        await cancelPending()
        guard date > .now else { return }
        guard await requestAuthorization() else { return }

        let alert = AlarmPresentation.Alert(
            title: "Time to feed \(babyName)",
            stopButton: AlarmButton(text: "Got it", textColor: .white, systemImageName: "checkmark")
        )
        let attributes = AlarmAttributes(
            presentation: AlarmPresentation(alert: alert),
            metadata: FeedAlarmMetadata(),
            tintColor: Color.orange
        )
        let configuration = AlarmManager.AlarmConfiguration.alarm(
            schedule: .fixed(date),
            attributes: attributes
        )

        let id = UUID()
        do {
            _ = try await AlarmManager.shared.schedule(id: id, configuration: configuration)
            UserDefaults.standard.set(id.uuidString, forKey: idKey)
            UserDefaults.standard.set(date.timeIntervalSince1970, forKey: dateKey)
        } catch {
            // Fall back to a notification so the reminder still arrives.
            await ReminderScheduler.schedule(at: date, title: "Time to feed \(babyName)", body: "Alarm couldn't be set; here's a reminder instead.")
        }
    }
}
