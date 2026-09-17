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

    static var recommendedPerFeedML: Double {
        get { UserDefaults.standard.double(forKey: recommendedPerFeedKey) }
        set { UserDefaults.standard.set(newValue, forKey: recommendedPerFeedKey) }
    }

    /// The amount a bottle should start at, in ml.
    ///
    /// A pinned amount wins, because a caregiver who says their baby takes
    /// 5 oz shouldn't be argued with. Otherwise the guidance's per-feed amount,
    /// which follows the baby's weight and age, rounded to the unit's step so
    /// it reads as "2.5 oz" rather than "2.35 oz". Failing both – no weight and
    /// no birthday yet – a plain starting amount.
    static func defaultAmountML(
        for kind: FeedKind,
        unit: VolumeUnit,
        defaults: UserDefaults = .standard
    ) -> Double {
        let pinned = defaults.double(forKey: amountKey(for: kind))
        if pinned > 0 { return pinned }

        let recommended = defaults.double(forKey: recommendedPerFeedKey)
        if recommended > 0 {
            return unit.toMilliliters(unit.rounded(unit.fromMilliliters(recommended)))
        }
        return unit.toMilliliters(unit.defaultAmount)
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
