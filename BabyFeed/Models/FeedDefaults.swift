import Foundation

/// UserDefaults keys for preferences. Kept in one place so views and
/// settings agree on the spelling.
enum FeedDefaults {
    static let volumeUnit = "volumeUnit"
    static let lastNursingMinutes = "lastNursingMinutes"

    /// The guidance's per-feed amount, in ml, mirrored out of SwiftData by
    /// `FeedCoordinator` on every change.
    ///
    /// It lives in UserDefaults because the log sheet picks its starting amount
    /// in `init`, before SwiftData is reachable, and the Siri intent and the
    /// quick-log buttons need the same number. Same reason `BabyProfile`
    /// mirrors the name and birthday. 0 means there isn't enough known about
    /// the baby to recommend anything.
    static let recommendedPerFeedKey = "guidance.recommendedPerFeedML"

    /// A bottle amount the caregiver has pinned by hand, in ml.
    /// 0 – the default – means "follow the recommendation".
    static func amountKey(for kind: FeedKind) -> String {
        "defaultAmountML.\(kind.rawValue)"
    }

    /// What this caregiver actually tends to give for a kind, in ml – the
    /// median of recent feeds, mirrored out by `FeedCoordinator`. 0 when there
    /// isn't enough history to call it a habit.
    static func typicalKey(for kind: FeedKind) -> String {
        "typicalAmountML.\(kind.rawValue)"
    }

    static var recommendedPerFeedML: Double {
        get { UserDefaults.standard.double(forKey: recommendedPerFeedKey) }
        set { UserDefaults.standard.set(newValue, forKey: recommendedPerFeedKey) }
    }

    /// Where a bottle's starting amount comes from.
    enum AmountSource: Equatable {
        /// The caregiver pinned a number in Settings.
        case pinned
        /// The median of what they actually give, once it's a habit.
        case learned
        /// The guidance's per-feed amount from weight and age.
        case recommended
        /// Nothing known about the baby yet.
        case fallback
    }

    /// The amount a bottle should start at, in ml, and where it came from.
    ///
    /// In order:
    /// 1. A pinned amount, because an explicit choice shouldn't be argued with.
    /// 2. What this caregiver actually tends to give. If every bottle is 20 ml,
    ///    offering 70 is just something to tap past – their baby beats a rule
    ///    of thumb, and this moves as they do.
    /// 3. The guidance's per-feed amount, which follows weight and age.
    /// 4. A plain starting amount, with no birthday or weight to work from.
    ///
    /// The recommendation stays visible either way – in the log sheet note and
    /// in Settings – so following the habit never hides the guidance.
    static func amount(
        for kind: FeedKind,
        unit: VolumeUnit,
        defaults: UserDefaults = .standard
    ) -> (ml: Double, source: AmountSource) {
        let pinned = defaults.double(forKey: amountKey(for: kind))
        if pinned > 0 { return (pinned, .pinned) }

        let learned = defaults.double(forKey: typicalKey(for: kind))
        if learned > 0 { return (snap(learned, unit: unit), .learned) }

        let recommended = defaults.double(forKey: recommendedPerFeedKey)
        if recommended > 0 { return (snap(recommended, unit: unit), .recommended) }

        return (unit.toMilliliters(unit.defaultAmount), .fallback)
    }

    static func defaultAmountML(
        for kind: FeedKind,
        unit: VolumeUnit,
        defaults: UserDefaults = .standard
    ) -> Double {
        amount(for: kind, unit: unit, defaults: defaults).ml
    }

    /// Rounded to the unit's step, so it reads as "2.5 oz" not "2.35 oz".
    private static func snap(_ ml: Double, unit: VolumeUnit) -> Double {
        unit.toMilliliters(unit.rounded(unit.fromMilliliters(ml)))
    }

    static func setTypicalAmountML(_ ml: Double?, for kind: FeedKind, defaults: UserDefaults = .standard) {
        defaults.set(ml ?? 0, forKey: typicalKey(for: kind))
    }

    /// True when this kind is following the recommendation rather than a pin.
    static func followsRecommendation(for kind: FeedKind, defaults: UserDefaults = .standard) -> Bool {
        defaults.double(forKey: amountKey(for: kind)) <= 0
    }

    /// Pins an amount by hand. Pass nil to go back to the recommendation.
    static func setDefaultAmountML(_ ml: Double?, for kind: FeedKind, defaults: UserDefaults = .standard) {
        defaults.set(ml ?? 0, forKey: amountKey(for: kind))
    }

    static let didClearLegacyPinsKey = "defaultAmountML.didClearLegacyPins"

    /// Clears amounts left behind by the older "each feed you save becomes the
    /// next default" behaviour, once.
    ///
    /// Those values were written automatically by saving a feed, not chosen, so
    /// treating them as deliberate pins would mean the recommendation never
    /// appeared for anyone who had already used the app. A caregiver who really
    /// wants a fixed amount can pin one in Settings, and that pin is set
    /// after this has run so it survives.
    static func clearLegacyPinsIfNeeded(defaults: UserDefaults = .standard) {
        guard !defaults.bool(forKey: didClearLegacyPinsKey) else { return }
        for kind in FeedKind.allCases where kind.usesVolume {
            defaults.removeObject(forKey: amountKey(for: kind))
        }
        defaults.set(true, forKey: didClearLegacyPinsKey)
    }

    static func defaultNursingMinutes(defaults: UserDefaults = .standard) -> Int {
        let stored = defaults.integer(forKey: lastNursingMinutes)
        return stored > 0 ? stored : 15
    }

    static func setDefaultNursingMinutes(_ minutes: Int, defaults: UserDefaults = .standard) {
        defaults.set(minutes, forKey: lastNursingMinutes)
    }
}
