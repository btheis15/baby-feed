import Foundation

/// How the baby is mostly fed. Drives which intake rule of thumb applies.
enum FeedingStyle: String, CaseIterable, Identifiable {
    case formula
    case breastMilk
    case mixed

    var id: String { rawValue }

    var title: String {
        switch self {
        case .formula: "Mostly formula"
        case .breastMilk: "Mostly breast milk"
        case .mixed: "A mix of both"
        }
    }
}

/// Published rules of thumb for how much a baby needs. Everything here is
/// guidance, not medical advice; the UI says so and points to the pediatrician.
///
/// Sources (see PLAN.md for links):
/// - AAP / HealthyChildren.org, "Amount and Schedule of Baby Formula Feedings":
///   about 2½ oz (75 ml) of formula per day for every pound (453 g) of body weight,
///   usually no more than about 32 oz (960 ml) in 24 hours.
/// - AAP / CDC age-based typical amounts: 1–2 oz every 2–3 h in the first days;
///   2–3 oz every 3–4 h in the first weeks; 3–4 oz by the end of month 1;
///   roughly +1 oz per month; 6–8 oz at 4–5 feeds by 6 months.
/// - AAP breastfeeding: at least 8–12 feeds per 24 h for newborns; wake a sleepy
///   newborn if it has been more than about 3–4 hours since the last feed until
///   birth weight is regained.
/// - Research summarized by KellyMom: exclusively breastfed babies 1–6 months
///   take about 25 oz (750 ml) a day, typical range 19–30 oz (570–900 ml).
enum FeedingGuidance {
    static let mlPerOunce = 29.5735

    /// AAP formula rule: 2.5 oz per pound per day, expressed per gram.
    static let formulaMLPerGramPerDay = 2.5 * mlPerOunce / 453.59237
    /// AAP ceiling: about 32 oz per day.
    static let maxDailyML = 32 * mlPerOunce
    /// Exclusively breastfed, 1–6 months.
    static let breastMilkAverageDailyML = 25 * mlPerOunce
    static let breastMilkDailyRangeML = (19 * mlPerOunce)...(30 * mlPerOunce)
    /// After this many days the breast-milk plateau rule applies.
    static let breastMilkPlateauStartDays = 28

    /// Typical amounts by age, per AAP/CDC.
    struct AgeBand: Equatable {
        let title: String
        /// Exclusive upper bound in days; nil = open-ended.
        let upToDays: Int?
        let perFeedOunces: ClosedRange<Double>
        let feedsPerDay: ClosedRange<Int>
        let hoursBetween: ClosedRange<Double>
        let note: String

        var perFeedML: ClosedRange<Double> {
            (perFeedOunces.lowerBound * mlPerOunce)...(perFeedOunces.upperBound * mlPerOunce)
        }
        var typicalFeedsPerDay: Int { (feedsPerDay.lowerBound + feedsPerDay.upperBound) / 2 }
        var typicalHoursBetween: Double { (hoursBetween.lowerBound + hoursBetween.upperBound) / 2 }
    }

    static let ageBands: [AgeBand] = [
        AgeBand(title: "First few days", upToDays: 4, perFeedOunces: 1...2, feedsPerDay: 8...12, hoursBetween: 2...3,
                note: "Tiny tummy. Small, frequent feeds; colostrum or 1–2 oz of formula every 2–3 hours."),
        AgeBand(title: "First 2 weeks", upToDays: 14, perFeedOunces: 2...3, feedsPerDay: 8...12, hoursBetween: 2.5...3.5,
                note: "Feed at least 8–12 times a day. Wake the baby if it has been more than 3–4 hours until birth weight is regained."),
        AgeBand(title: "2–4 weeks", upToDays: 28, perFeedOunces: 2.5...4, feedsPerDay: 8...10, hoursBetween: 3...4,
                note: "Amounts climb toward 3–4 oz per feed by the end of the first month."),
        AgeBand(title: "1–2 months", upToDays: 61, perFeedOunces: 4...5, feedsPerDay: 6...8, hoursBetween: 3...4,
                note: "A fairly regular rhythm of roughly every 3–4 hours is common."),
        AgeBand(title: "2–4 months", upToDays: 122, perFeedOunces: 4...6, feedsPerDay: 5...7, hoursBetween: 3.5...4.5,
                note: "Many babies over about 12 lb start dropping a middle-of-the-night feed."),
        AgeBand(title: "4–6 months", upToDays: 183, perFeedOunces: 5...7, feedsPerDay: 5...6, hoursBetween: 4...5,
                note: "Bigger feeds, fewer of them. Solids are still to come."),
        AgeBand(title: "6+ months", upToDays: nil, perFeedOunces: 6...8, feedsPerDay: 4...5, hoursBetween: 4...6,
                note: "6–8 oz at 4–5 feeds a day alongside first solids."),
    ]

    static func ageBand(forAgeDays days: Int) -> AgeBand {
        ageBands.first { band in
            guard let upTo = band.upToDays else { return true }
            return days < upTo
        } ?? ageBands[ageBands.count - 1]
    }

    /// The number the home screen is built around.
    struct DailyTarget: Equatable {
        /// Best single estimate for 24 hours, in ml.
        let targetML: Double
        /// Typical range, when the rule gives one.
        let rangeML: ClosedRange<Double>?
        /// Feeds per day the per-feed number assumes.
        let feedsPerDay: Int
        /// One-line explanation shown under the number.
        let basis: String

        var perFeedML: Double { targetML / Double(max(1, feedsPerDay)) }
    }

    /// Daily target from weight and/or age. Returns nil when there is nothing to go on.
    /// - Parameters:
    ///   - weightGrams: most recent weight, if any.
    ///   - ageDays: age in days, if the birthday is known.
    ///   - style: how the baby is mostly fed.
    ///   - feedsPerDay: caregiver's setting for how many feeds a day to plan on; 0 = use the age-typical number.
    static func dailyTarget(weightGrams: Double?, ageDays: Int?, style: FeedingStyle, feedsPerDay: Int = 0) -> DailyTarget? {
        let band = ageDays.map(ageBand(forAgeDays:))
        let feeds = feedsPerDay > 0 ? feedsPerDay : (band?.typicalFeedsPerDay ?? 8)

        // Exclusively breastfed babies plateau at ~25 oz/day after the first month,
        // regardless of weight (they do not follow the formula rule).
        if style == .breastMilk, let ageDays, ageDays >= breastMilkPlateauStartDays {
            return DailyTarget(
                targetML: breastMilkAverageDailyML,
                rangeML: breastMilkDailyRangeML,
                feedsPerDay: feeds,
                basis: "Breastfed babies 1–6 months take about 25 oz a day (typically 19–30 oz)."
            )
        }

        if let weightGrams, weightGrams > 0 {
            let raw = weightGrams * formulaMLPerGramPerDay
            let target = min(raw, maxDailyML)
            let pounds = weightGrams / 453.59237
            var basis = "2½ oz per pound per day (AAP) at \(pounds.formatted(.number.precision(.fractionLength(1)))) lb"
            if raw > maxDailyML { basis += ", capped at 32 oz" }
            // Early days: babies ramp up, so also show the age-typical range as context.
            var range: ClosedRange<Double>? = nil
            if let band, let ageDays, ageDays < 14 {
                let lo = band.perFeedML.lowerBound * Double(band.feedsPerDay.lowerBound)
                let hi = band.perFeedML.upperBound * Double(band.feedsPerDay.upperBound)
                range = lo...min(hi, maxDailyML)
                basis += ". In the first two weeks intake ramps up from a few ounces a day."
            }
            return DailyTarget(targetML: target, rangeML: range, feedsPerDay: feeds, basis: basis)
        }

        if let band {
            let lo = band.perFeedML.lowerBound * Double(band.feedsPerDay.lowerBound)
            let hi = min(band.perFeedML.upperBound * Double(band.feedsPerDay.upperBound), maxDailyML)
            let mid = (lo + hi) / 2
            return DailyTarget(
                targetML: mid,
                rangeML: lo...hi,
                feedsPerDay: feeds,
                basis: "Typical for \(band.title.lowercased()) (AAP/CDC). Add a weight for a personal target."
            )
        }

        return nil
    }

    /// Suggested hours between feeds for an age, used as the reminder default.
    static func suggestedIntervalHours(ageDays: Int?) -> Double {
        guard let ageDays else { return 3 }
        return ageBand(forAgeDays: ageDays).typicalHoursBetween
    }

    /// AAP: wake a newborn who has gone this long without feeding (first weeks).
    static let newbornMaxGapHours: Double = 4

    /// Expected weight pattern: lose up to ~7–10% in the first days, regain birth
    /// weight by about 10–14 days, then gain roughly 5–7 oz (150–200 g) a week
    /// for the first few months.
    static let typicalWeeklyGainGrams: ClosedRange<Double> = 150...200
}
