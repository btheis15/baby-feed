import Foundation

/// Pure weight-trend helpers. No SwiftUI, no persistence – easy to test.
///
/// Every function takes weights **newest first**, matching the `@Query(sort:
/// \WeightEntry.date, order: .reverse)` the views use.
enum WeightStats {
    /// The step between two consecutive weigh-ins.
    struct Change: Equatable {
        /// Signed change in grams: positive is a gain.
        var grams: Double
        /// Whole calendar days between the two weigh-ins.
        var days: Int
        /// Gain per week implied by this step, or nil when the two weigh-ins
        /// are too close together for the rate to mean anything.
        var gramsPerWeek: Double?
    }

    /// Minimum span before a two-point gain rate is worth showing. Weighing a
    /// newborn twice in a day says more about the scale than the baby.
    private static let minimumWeeks = 0.2

    /// Latest weight minus the one before it.
    static func lastChange(_ weights: [WeightEntry], calendar: Calendar = .current) -> Change? {
        guard weights.count >= 2 else { return nil }
        let latest = weights[0], previous = weights[1]
        let grams = latest.grams - previous.grams
        let weeks = latest.date.timeIntervalSince(previous.date) / (7 * 24 * 3600)
        let days = calendar.dateComponents(
            [.day],
            from: calendar.startOfDay(for: previous.date),
            to: calendar.startOfDay(for: latest.date)
        ).day ?? 0

        return Change(
            grams: grams,
            days: days,
            gramsPerWeek: weeks > minimumWeeks ? grams / weeks : nil
        )
    }

    /// Change from the earliest recorded weight to the latest. With a birth
    /// weight as the first entry this is the total gain since birth.
    static func changeSinceFirst(_ weights: [WeightEntry]) -> Double? {
        guard weights.count >= 2, let latest = weights.first, let first = weights.last else { return nil }
        return latest.grams - first.grams
    }

    /// Average gain per week across the whole log, or nil when the log spans
    /// too short a time. Steadier than `lastChange` once there are a few entries.
    static func overallGramsPerWeek(_ weights: [WeightEntry]) -> Double? {
        guard weights.count >= 2, let latest = weights.first, let first = weights.last else { return nil }
        let weeks = latest.date.timeIntervalSince(first.date) / (7 * 24 * 3600)
        guard weeks > minimumWeeks else { return nil }
        return (latest.grams - first.grams) / weeks
    }
}
