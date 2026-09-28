import Foundation

/// "Is she getting enough?" for the first six weeks, as the numbers Today
/// shows: the last 24 hours of wet and dirty diapers and feeds, each against
/// what's expected at this age.
///
/// A count below the expectation is shown as a plain number, never as a
/// warning: a missed log is not a sick baby. The one alarm it raises is the
/// guidance's own red flag, no wet diaper in more than 8 hours, and only when
/// the family is clearly still logging.
struct EnoughSummary: Equatable {
    struct Count: Equatable {
        let count: Int
        /// Nil when nothing is expected at this age (stools before day 5).
        let expected: ClosedRange<Int>?

        var meetsExpectation: Bool { expected.map { count >= $0.lowerBound } ?? false }
    }

    let wet: Count
    let dirty: Count
    let feeds: Count
    /// Set when the last wet diaper was more than 8 hours ago and the log
    /// kept going after it: the red flag, with when the last one was.
    let noWetSince: Date?

    /// The block shows for the first six weeks; after that it lives on the
    /// Baby tab.
    static let showsForDays = 42
    /// `IntakeGuidance`'s `no-urine` flag: no wet diaper in more than 8 hours.
    static let noWetFlagAfter: TimeInterval = 8 * 3600

    static func shows(ageDays: Int?) -> Bool {
        guard let ageDays else { return false }
        return (0..<showsForDays).contains(ageDays)
    }

    init(diapers: [DiaperEntry], feeds: [FeedEntry], ageDays: Int, now: Date) {
        let day = diapers.active(for: nil).within(24 * 3600, now: now)
        let tally = DiaperTally(day)
        wet = Count(count: tally.wet, expected: IntakeGuidance.expectedWet(ageDays: ageDays))
        dirty = Count(count: tally.dirty, expected: IntakeGuidance.expectedDirty(ageDays: ageDays))
        let recentFeeds = FeedStats.entries(feeds.active(for: nil), within: 24 * 3600, now: now)
        self.feeds = Count(count: recentFeeds.count,
                           expected: FeedingGuidance.ageBand(forAgeDays: ageDays).feedsPerDay)
        noWetSince = Self.noWetSince(diapers: diapers, feeds: feeds, now: now)
    }

    /// When the last wet diaper was, if that's more than 8 hours ago and
    /// something else was logged since. A family that stopped logging
    /// diapers altogether isn't told its baby is dry; neither is one whose
    /// last wet diaper was days ago, which is a gap in the log, not a reading.
    static func noWetSince(diapers: [DiaperEntry], feeds: [FeedEntry], now: Date) -> Date? {
        let active = diapers.active(for: nil).filter { $0.time <= now }
        guard let lastWet = active.filter({ $0.kind.countsAsWet }).map(\.time).max() else { return nil }
        let since = now.timeIntervalSince(lastWet)
        guard since > noWetFlagAfter, since <= 24 * 3600 else { return nil }
        let loggedSince = active.contains { $0.time > lastWet }
            || feeds.active(for: nil).contains { $0.startTime > lastWet && $0.startTime <= now }
        return loggedSince ? lastWet : nil
    }
}

/// Back to birth weight: the first number a pediatrician asks about. Most
/// babies lose up to 7–10% in the first days and are back by about 10–14
/// days (`IntakeGuidance.whatMatters`).
enum BirthWeightStatus: Equatable {
    /// No weigh-in on the birthday or the day after.
    case noBirthWeight
    /// A birth weight and nothing since.
    case birthOnly(grams: Double)
    /// The latest weigh-in, still under birth weight.
    case below(birthGrams: Double, latestGrams: Double, onDay: Int)
    /// Back at or above birth weight, on this day of life.
    case regained(onDay: Int)
    /// Weighed at two weeks or later and still under: the guidance's
    /// `birth-weight` red flag.
    case notRegained(birthGrams: Double, latestGrams: Double, onDay: Int)

    /// The line shows for the first three weeks.
    static let showsForDays = 21
    /// "Not back to birth weight by about two weeks."
    static let expectedByDay = 14

    init(weights: [WeightEntry], birthDate: Date?, calendar: Calendar) {
        guard let birthDate else {
            self = .noBirthWeight
            return
        }
        let dated = weights.active(for: nil)
            .map { (day: RelativeAge.days(from: birthDate, to: $0.date, calendar: calendar), weight: $0) }
            .sorted { $0.weight.date < $1.weight.date }
        // The earliest weigh-in on the birthday or the day after.
        guard let birth = dated.first(where: { (0...1).contains($0.day) }) else {
            self = .noBirthWeight
            return
        }
        let later = dated.filter { $0.weight.date > birth.weight.date && $0.day >= 1 }
        if let back = later.first(where: { $0.weight.grams >= birth.weight.grams }) {
            self = .regained(onDay: back.day)
        } else if let latest = later.last {
            self = latest.day >= Self.expectedByDay
                ? .notRegained(birthGrams: birth.weight.grams, latestGrams: latest.weight.grams, onDay: latest.day)
                : .below(birthGrams: birth.weight.grams, latestGrams: latest.weight.grams, onDay: latest.day)
        } else {
            self = .birthOnly(grams: birth.weight.grams)
        }
    }

    var isRegained: Bool {
        if case .regained = self { return true }
        return false
    }

    /// Whether there's a birth weight to measure from at all.
    var hasBirthWeight: Bool { self != .noBirthWeight }

    /// Change from birth weight, as a fraction: −0.04 for 4% down.
    static func change(birthGrams: Double, latestGrams: Double) -> Double {
        birthGrams > 0 ? (latestGrams - birthGrams) / birthGrams : 0
    }

    /// "−4%", rounded to a whole percent, with a real minus sign.
    static func percentText(_ change: Double) -> String {
        let percent = Int((change * 100).rounded())
        return percent < 0 ? "−\(-percent)%" : "+\(percent)%"
    }

    /// The line on Today, or nil when there's nothing worth a line.
    func line(weightUnit: WeightUnit) -> String? {
        switch self {
        case .noBirthWeight:
            return nil
        case .birthOnly(let grams):
            return "Birth weight \(weightUnit.format(grams: grams)) · most babies are back to it by day 10–14"
        case .below(let birth, let latest, let day):
            let change = Self.percentText(Self.change(birthGrams: birth, latestGrams: latest))
            return "Birth \(weightUnit.format(grams: birth)) → \(weightUnit.format(grams: latest)) on day \(day) (\(change)) · most babies are back by day 10–14"
        case .regained(let day):
            return "Back to birth weight ✓ on day \(day)"
        case .notRegained(let birth, let latest, let day):
            let change = Self.percentText(Self.change(birthGrams: birth, latestGrams: latest))
            return "\(weightUnit.format(grams: latest)) on day \(day) (\(change) from birth)"
        }
    }
}

/// Which side to start the next nursing on: the other one from last time.
enum NextSide {
    /// Right after a left feed, left after a right one, and nothing after
    /// both or with no side recorded, where a guess would just be noise.
    static func suggestion(after feeds: [FeedEntry]) -> NursingSide? {
        let lastNursing = feeds.active(for: nil)
            .filter { $0.kind == .nursing }
            .max { $0.startTime < $1.startTime }
        switch lastNursing?.side {
        case .left: return .right
        case .right: return .left
        case .both, nil: return nil
        }
    }

    /// The side the last nursing feed used, for the hero's small line.
    static func last(in feeds: [FeedEntry]) -> NursingSide? {
        feeds.active(for: nil)
            .filter { $0.kind == .nursing }
            .max { $0.startTime < $1.startTime }?
            .side
    }
}
