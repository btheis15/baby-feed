import Foundation

/// UserDefaults-backed preferences that several parts of the app read.
/// Views bind to the keys with @AppStorage; services read the static accessors.
enum AppSettings {
    static let remindersEnabledKey = "reminders.enabled"
    static let intervalMinutesKey = "reminders.intervalMinutes"
    static let useAlarmKey = "reminders.useAlarm"
    static let liveActivityKey = "reminders.liveActivity"
    static let feedingStyleKey = "guidance.feedingStyle"
    static let feedsPerDayKey = "guidance.feedsPerDay"
    static let weightUnitKey = "weightUnit"
    static let currentBabyIDKey = "baby.currentID"
    static let displayNameKey = "sync.displayName"

    static let defaultIntervalMinutes = 180
    static let intervalChoices = [120, 150, 180, 210, 240]

    private static var defaults: UserDefaults { .standard }

    static var remindersEnabled: Bool { defaults.bool(forKey: remindersEnabledKey) }

    static var intervalMinutes: Int {
        let stored = defaults.integer(forKey: intervalMinutesKey)
        return stored > 0 ? stored : defaultIntervalMinutes
    }

    static var interval: TimeInterval { Double(intervalMinutes) * 60 }

    /// Ring a real alarm (AlarmKit) instead of a notification.
    static var useAlarm: Bool { defaults.bool(forKey: useAlarmKey) }

    /// Dynamic Island / Lock Screen countdown. On by default.
    static var liveActivityEnabled: Bool {
        defaults.object(forKey: liveActivityKey) == nil ? true : defaults.bool(forKey: liveActivityKey)
    }

    static var feedingStyle: FeedingStyle {
        FeedingStyle(rawValue: defaults.string(forKey: feedingStyleKey) ?? "") ?? .formula
    }

    /// 0 means "use the age-typical number".
    static var feedsPerDay: Int { defaults.integer(forKey: feedsPerDayKey) }

    static var volumeUnit: VolumeUnit {
        VolumeUnit(rawValue: defaults.string(forKey: FeedDefaults.volumeUnit) ?? "") ?? .ounces
    }

    static var weightUnit: WeightUnit {
        WeightUnit(rawValue: defaults.string(forKey: weightUnitKey) ?? "") ?? .poundsOunces
    }

    /// The baby whose log is showing. Set by `BabyStore`.
    static var currentBabyID: UUID? {
        get { defaults.string(forKey: currentBabyIDKey).flatMap(UUID.init(uuidString:)) }
        set { defaults.set(newValue?.uuidString, forKey: currentBabyIDKey) }
    }

    /// How this caregiver appears to others ("Brian").
    static var displayName: String {
        get { defaults.string(forKey: displayNameKey) ?? "" }
        set { defaults.set(newValue, forKey: displayNameKey) }
    }

    static func nextDue(after lastFeed: Date) -> Date {
        lastFeed.addingTimeInterval(interval)
    }
}
