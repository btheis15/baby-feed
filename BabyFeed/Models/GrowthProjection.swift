import Foundation

/// An estimate of what the baby weighs *now*, carried forward from the last
/// real weigh-in on the assumption that babies tend to track their percentile.
///
/// This exists because the daily feeding target is otherwise frozen at the last
/// weigh-in, and a newborn gains 5–7 oz a week – three weeks after a visit the
/// target is meaningfully stale.
struct GrowthProjection: Equatable {
    /// The weigh-in this is anchored to.
    var anchorGrams: Double
    var anchorDate: Date
    /// Percentile at the anchor weigh-in, 0–100.
    var anchorPercentile: Double
    /// Best estimate of the weight now, in grams.
    var estimatedGrams: Double
    /// Plausible spread now, from the band either side of the anchor percentile.
    var rangeGrams: ClosedRange<Double>
    /// Whole days since the anchor weigh-in.
    var daysSinceAnchor: Int
    /// True once the anchor is too old to keep extrapolating from honestly.
    var isStale: Bool
    /// True when the anchor weigh-in was in the first two weeks, so the
    /// estimate follows the newborn dip and regain (`NewbornWeight`) rather
    /// than a straight climb along the percentile.
    var followsNewbornDip = false

    /// True when the estimate is just the weigh-in itself, because it happened
    /// today. Callers should say "weighed" rather than "estimated" then.
    var isMeasured: Bool { daysSinceAnchor == 0 }
}

/// The first two weeks: most babies lose some weight in the first days, up to
/// 7–10% of their birth weight, and are back to it by about 10–14 days (AAP,
/// `IntakeGuidance.whatMatters`). Carrying a birth weight forward along its
/// percentile instead would say a 5-day-old has gained, and push the feeding
/// target up just when intake is still ramping.
///
/// The estimate is a shape, not a measurement: down to `typicalLoss` by day 3,
/// back to birth weight by day 12, the middle of 10–14. The range around it
/// runs from no loss at all to `largestExpectedLoss`.
enum NewbornWeight {
    static let typicalLoss = 0.07
    static let largestExpectedLoss = 0.10
    static let lowestOnDay = 3
    static let regainedByDay = 12
    /// After this the usual percentile projection takes over.
    static let settledByDay = 14
    /// Where the 7–10% and 10–14 days come from.
    static let sourceID = "aap-enough-milk"

    /// Weight on a day of life as a fraction of birth weight.
    static func factor(day: Int, loss: Double = typicalLoss) -> Double {
        if day <= 0 { return 1 }
        if day <= lowestOnDay { return 1 - loss * Double(day) / Double(lowestOnDay) }
        if day < regainedByDay {
            return 1 - loss * Double(regainedByDay - day) / Double(regainedByDay - lowestOnDay)
        }
        return 1
    }

    /// "Most babies lose up to 7–10% of their birth weight in the first days
    /// and are back to it by 10–14 days (AAP)."
    static let explanation = "Most babies lose up to 7–10% of their birth weight in the first days and are back to it by 10–14 days (AAP)."
}

/// How the percentile moved between the last two weigh-ins.
struct GrowthDrift: Equatable {
    var fromPercentile: Double
    var toPercentile: Double
    var fromDate: Date
    var toDate: Date

    var deltaPercentile: Double { toPercentile - fromPercentile }

    /// Signed change in standard deviations, which is the meaningful measure –
    /// dropping 10 percentile points near the median is a much smaller move
    /// than dropping 10 points near the 3rd.
    var deltaZ: Double {
        GrowthStandard.zScore(percentile: toPercentile) - GrowthStandard.zScore(percentile: fromPercentile)
    }

    /// True when the baby has dropped roughly a full major centile channel.
    /// That is the thing a pediatrician wants to hear about, so the app says so
    /// plainly instead of smoothing it over.
    var hasFallenAChannel: Bool { deltaZ <= -GrowthProjector.channelZ }
}

/// Turns weigh-ins into a projection. Pure – no SwiftUI, no persistence.
enum GrowthProjector {
    /// Half-width of the estimate band, in standard deviations. Babies track
    /// their channel loosely, and the scale at home isn't the one at the clinic,
    /// so a single projected number would be false precision. A quarter of an
    /// SD is narrow enough to be useful and wide enough to be honest.
    static let bandZ = 0.25

    /// One major centile channel, in standard deviations – the spacing WHO uses
    /// between adjacent printed centiles (e.g. 3rd to 15th).
    static let channelZ = 0.67

    /// Stop extrapolating after three weeks and ask for a fresh weight.
    /// Projecting six weeks off one weigh-in stops being reassurance and starts
    /// being a guess wearing a number.
    static let staleAfterDays = 21

    /// Below this percentile, ask whether the baby was born early.
    ///
    /// A preterm baby plotted against term standards reads alarmingly small –
    /// an average four-week-old shown at ten weeks actual age falls under the
    /// 3rd centile. Rather than put a "born early?" question in front of every
    /// parent, the app asks here, where a low number would otherwise worry
    /// someone whose baby is in fact growing normally for their corrected age.
    static let askAboutPretermBelowPercentile = 10.0

    /// Projects today's weight from the most recent weigh-in.
    ///
    /// `weights` must be newest first. Returns nil when there's nothing to
    /// anchor to, the sex isn't known, or the age falls outside WHO's tables.
    static func project(
        weights: [WeightEntry],
        profile: BabyProfile,
        now: Date = .now,
        calendar: Calendar = .current
    ) -> GrowthProjection? {
        guard let sex = profile.sex.known, let anchor = weights.first else { return nil }
        let days = calendar.dateComponents(
            [.day],
            from: calendar.startOfDay(for: anchor.date),
            to: calendar.startOfDay(for: now)
        ).day ?? 0

        // Weighed in the first two weeks: follow the newborn dip. Not for a
        // baby born early, who is plotted at corrected age below and before
        // the due date isn't estimated at all.
        if !profile.isPreterm, let birthDate = profile.birthDate,
           let anchorDay = profile.ageInDays(on: anchor.date, calendar: calendar),
           let nowDay = profile.ageInDays(on: now, calendar: calendar),
           anchorDay < NewbornWeight.settledByDay, nowDay >= anchorDay {
            // What the weigh-in implies the birth weight was (the weight
            // itself, for a birth weight).
            let birthGrams = anchor.grams / NewbornWeight.factor(day: anchorDay)
            if nowDay < NewbornWeight.settledByDay {
                guard let birthAge = profile.growthAgeDays(on: birthDate),
                      let z = GrowthStandard.zScore(grams: birthGrams, ageDays: max(0, birthAge), sex: sex)
                else { return nil }
                let estimates = [0, NewbornWeight.typicalLoss, NewbornWeight.largestExpectedLoss].map { loss in
                    anchor.grams * NewbornWeight.factor(day: nowDay, loss: loss) / NewbornWeight.factor(day: anchorDay, loss: loss)
                }
                return GrowthProjection(
                    anchorGrams: anchor.grams,
                    anchorDate: anchor.date,
                    anchorPercentile: GrowthStandard.normalCDF(z) * 100,
                    estimatedGrams: days == 0 ? anchor.grams : estimates[1],
                    rangeGrams: estimates.min()!...estimates.max()!,
                    daysSinceAnchor: max(0, days),
                    isStale: false,
                    followsNewbornDip: true
                )
            }
            // Past the dip: that birth weight, reached again by about two
            // weeks, carried on along its percentile from there.
            guard let settledDate = calendar.date(byAdding: .day, value: NewbornWeight.settledByDay,
                                                  to: calendar.startOfDay(for: birthDate)),
                  let settledAge = profile.growthAgeDays(on: settledDate),
                  let nowAge = profile.growthAgeDays(on: now),
                  let z = GrowthStandard.zScore(grams: birthGrams, ageDays: settledAge, sex: sex),
                  let estimate = GrowthStandard.grams(zScore: z, ageDays: nowAge, sex: sex),
                  let low = GrowthStandard.grams(zScore: z - bandZ, ageDays: nowAge, sex: sex),
                  let high = GrowthStandard.grams(zScore: z + bandZ, ageDays: nowAge, sex: sex)
            else { return nil }
            return GrowthProjection(
                anchorGrams: anchor.grams,
                anchorDate: anchor.date,
                anchorPercentile: GrowthStandard.normalCDF(z) * 100,
                estimatedGrams: estimate,
                rangeGrams: min(low, high)...max(low, high),
                daysSinceAnchor: max(0, days),
                isStale: days > staleAfterDays
            )
        }

        guard let anchorAge = profile.growthAgeDays(on: anchor.date),
              let nowAge = profile.growthAgeDays(on: now),
              let z = GrowthStandard.zScore(grams: anchor.grams, ageDays: anchorAge, sex: sex),
              let estimate = GrowthStandard.grams(zScore: z, ageDays: nowAge, sex: sex),
              let low = GrowthStandard.grams(zScore: z - bandZ, ageDays: nowAge, sex: sex),
              let high = GrowthStandard.grams(zScore: z + bandZ, ageDays: nowAge, sex: sex)
        else { return nil }

        return GrowthProjection(
            anchorGrams: anchor.grams,
            anchorDate: anchor.date,
            anchorPercentile: GrowthStandard.normalCDF(z) * 100,
            // On the day of the weigh-in, report the measurement itself rather
            // than a projection that rounds it.
            estimatedGrams: days == 0 ? anchor.grams : estimate,
            rangeGrams: min(low, high)...max(low, high),
            daysSinceAnchor: max(0, days),
            isStale: days > staleAfterDays
        )
    }

    /// Percentile drift between the two most recent weigh-ins, for re-anchoring
    /// after a doctor's visit. Nil with fewer than two, or when either falls
    /// outside the tables.
    static func drift(weights: [WeightEntry], profile: BabyProfile) -> GrowthDrift? {
        guard let sex = profile.sex.known, weights.count >= 2 else { return nil }
        let latest = weights[0], previous = weights[1]
        guard let latestAge = profile.growthAgeDays(on: latest.date),
              let previousAge = profile.growthAgeDays(on: previous.date),
              let to = GrowthStandard.percentile(grams: latest.grams, ageDays: latestAge, sex: sex),
              let from = GrowthStandard.percentile(grams: previous.grams, ageDays: previousAge, sex: sex)
        else { return nil }

        return GrowthDrift(
            fromPercentile: from,
            toPercentile: to,
            fromDate: previous.date,
            toDate: latest.date
        )
    }

    /// Days until a fresh weigh-in is worth taking, or nil when one is due.
    static func daysUntilFreshWeight(_ projection: GrowthProjection) -> Int? {
        let remaining = staleAfterDays - projection.daysSinceAnchor
        return remaining > 0 ? remaining : nil
    }

    /// "48th", "3rd", "72nd" – percentiles read better as ordinals.
    static func ordinal(percentile: Double) -> String {
        let value = max(1, min(99, Int(percentile.rounded())))
        let suffix: String
        switch (value % 10, value % 100) {
        case (_, 11), (_, 12), (_, 13): suffix = "th"
        case (1, _): suffix = "st"
        case (2, _): suffix = "nd"
        case (3, _): suffix = "rd"
        default: suffix = "th"
        }
        return "\(value)\(suffix)"
    }
}
