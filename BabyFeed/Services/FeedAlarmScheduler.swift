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
        guard let raw = UserDefaults.standard.string(forKey: idKey), let id = UUID(uuidString: raw) else { return }
        try? await AlarmManager.shared.cancel(id: id)
        UserDefaults.standard.removeObject(forKey: idKey)
    }

    static func schedule(at date: Date, babyName: String) async {
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
        } catch {
            // Fall back to a notification so the reminder still arrives.
            await ReminderScheduler.schedule(at: date, title: "Time to feed \(babyName)", body: "Alarm couldn't be set; here's a reminder instead.")
        }
    }
}
