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
    /// Set once the first-run sharing card has been shown, so it's offered
    /// once and then never nags again.
    static let hasSeenSharingIntroKey = "sync.hasSeenSharingIntro"
    /// A TimeZone identifier, or empty for "follow the device".
    static let timeZoneKey = "timeZone.identifier"

    static let defaultIntervalMinutes = 180
    static let intervalChoices = [120, 150, 180, 210, 240]

    private static var defaults: UserDefaults { .standard }

    static var remindersEnabled: Bool { defaults.bool(forKey: remindersEnabledKey) }

    /// The interval typical for the baby's age, snapped to the choices offered.
    ///
    /// Falls back to three hours when there's no birthday to work from.
    static var suggestedIntervalMinutes: Int {
        let profile = BabyProfile.load(from: defaults)
        guard profile.birthDate != nil else { return defaultIntervalMinutes }
        let hours = FeedingGuidance.suggestedIntervalHours(ageDays: profile.ageInDays(calendar: calendar))
        let rounded = Int((hours * 60 / 30).rounded()) * 30
        return intervalChoices.min { abs($0 - rounded) < abs($1 - rounded) } ?? defaultIntervalMinutes
    }

    /// True when the interval is following the baby's age rather than a pin.
    static var followsSuggestedInterval: Bool {
        defaults.integer(forKey: intervalMinutesKey) <= 0
    }

    /// Minutes between feeds.
    ///
    /// 0 – the default – means "follow what's typical for this age", so the gap
    /// widens on its own as the baby grows instead of sitting at whatever was
    /// chosen in the first week. A non-zero value is a deliberate pin.
    static var intervalMinutes: Int {
        let stored = defaults.integer(forKey: intervalMinutesKey)
        return stored > 0 ? stored : suggestedIntervalMinutes
    }

    static var interval: TimeInterval { Double(intervalMinutes) * 60 }

    /// Resolves a raw stored value the same way, for views that read the key
    /// through `@AppStorage` so they re-render when it changes.
    static func resolvedIntervalMinutes(raw: Int) -> Int {
        raw > 0 ? raw : suggestedIntervalMinutes
    }

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

    /// The time zone the log reads in.
    ///
    /// Follows the device by default, so flying from Chicago to London shifts
    /// everything automatically. A caregiver who'd rather keep the log on home
    /// time – so "Today" doesn't split a night in half while travelling – can
    /// pin one in Settings.
    static var timeZone: TimeZone {
        guard let identifier = defaults.string(forKey: timeZoneKey), !identifier.isEmpty else {
            return .current
        }
        return TimeZone(identifier: identifier) ?? .current
    }

    /// True when the time zone is following the device rather than pinned.
    static var followsDeviceTimeZone: Bool {
        (defaults.string(forKey: timeZoneKey) ?? "").isEmpty
    }

    /// The calendar every user-facing date calculation should go through, so a
    /// pinned time zone reaches day grouping, "Today"/"Yesterday" and the
    /// day-part breakdown rather than only the clock face.
    static var calendar: Calendar {
        var calendar = Calendar.current
        calendar.timeZone = timeZone
        return calendar
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
