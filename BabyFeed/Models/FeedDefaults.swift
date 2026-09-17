import Foundation

/// UserDefaults keys for preferences. Kept in one place so views and
/// settings agree on the spelling.
enum FeedDefaults {
    static let volumeUnit = "volumeUnit"
    static let lastNursingMinutes = "lastNursingMinutes"

    /// Per-kind default bottle amount, stored in ml.
    static func amountKey(for kind: FeedKind) -> String {
        "defaultAmountML.\(kind.rawValue)"
    }

    static func defaultAmountML(for kind: FeedKind, unit: VolumeUnit, defaults: UserDefaults = .standard) -> Double {
        let stored = defaults.double(forKey: amountKey(for: kind))
        return stored > 0 ? stored : unit.toMilliliters(unit.defaultAmount)
    }

    static func setDefaultAmountML(_ ml: Double, for kind: FeedKind, defaults: UserDefaults = .standard) {
        defaults.set(ml, forKey: amountKey(for: kind))
    }

    static func defaultNursingMinutes(defaults: UserDefaults = .standard) -> Int {
        let stored = defaults.integer(forKey: lastNursingMinutes)
        return stored > 0 ? stored : 15
    }

    static func setDefaultNursingMinutes(_ minutes: Int, defaults: UserDefaults = .standard) {
        defaults.set(minutes, forKey: lastNursingMinutes)
    }
}
