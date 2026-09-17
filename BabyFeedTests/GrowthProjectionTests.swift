import Foundation
import SwiftData
import Testing
@testable import BabyFeed

struct GrowthProjectionTests {
    private let kg = GrowthStandard.gramsPerKilogram
    private let birth = Date(timeIntervalSince1970: 1_700_000_000)

    private var utc: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }

    private func makeContext() throws -> ModelContext {
        let container = try ModelContainer(
            for: WeightEntry.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        return ModelContext(container)
    }

    private func profile(sex: BabySex = .male, dueDate: Date? = nil) -> BabyProfile {
        BabyProfile(name: "Sam", birthDate: birth, sex: sex, dueDate: dueDate)
    }

    /// Weigh-ins newest first, dated by days after birth.
    private func weights(_ specs: [(dayOfLife: Double, grams: Double)], in context: ModelContext) -> [WeightEntry] {
        let entries = specs.map { spec in
            WeightEntry(date: birth.addingTimeInterval(spec.dayOfLife * 24 * 3600), grams: spec.grams)
        }
        entries.forEach { context.insert($0) }
        return entries
    }

    @Test func projectsForwardAlongThePercentileChannel() throws {
        let context = try makeContext()
        // A boy on the median at 2 weeks.
        let median2w = try #require(GrowthStandard.grams(percentile: 50, ageDays: 14, sex: .male))
        let log = weights([(14, median2w)], in: context)

        // Four weeks old now, two weeks after the weigh-in.
        let now = birth.addingTimeInterval(28 * 24 * 3600)
        let projection = try #require(GrowthProjector.project(weights: log, profile: profile(), now: now, calendar: utc))

        #expect(abs(projection.anchorPercentile - 50) < 0.001)
        #expect(projection.daysSinceAnchor == 14)
        #expect(!projection.isMeasured)
        // Still on the median, so the estimate is the median at 4 weeks - and
        // materially heavier than the weigh-in it came from.
        let median4w = try #require(GrowthStandard.grams(percentile: 50, ageDays: 28, sex: .male))
        #expect(abs(projection.estimatedGrams - median4w) < 1)
        #expect(projection.estimatedGrams > projection.anchorGrams)
    }

    @Test func rangeBracketsTheEstimate() throws {
        let context = try makeContext()
        let log = weights([(14, 4.2 * kg)], in: context)
        let now = birth.addingTimeInterval(24 * 24 * 3600)
        let projection = try #require(GrowthProjector.project(weights: log, profile: profile(), now: now, calendar: utc))

        #expect(projection.rangeGrams.contains(projection.estimatedGrams))
        #expect(projection.rangeGrams.lowerBound < projection.estimatedGrams)
        #expect(projection.rangeGrams.upperBound > projection.estimatedGrams)
    }

    @Test func onTheDayOfAWeighInTheEstimateIsTheMeasurement() throws {
        let context = try makeContext()
        let log = weights([(14, 4.321 * kg)], in: context)
        // Later the same calendar day. The base timestamp is 22:13 UTC, so this
        // has to stay under two hours to avoid rolling into tomorrow.
        let now = birth.addingTimeInterval(14 * 24 * 3600 + 3600)
        let projection = try #require(GrowthProjector.project(weights: log, profile: profile(), now: now, calendar: utc))

        #expect(projection.isMeasured)
        #expect(projection.estimatedGrams == 4.321 * kg)
        #expect(!projection.isStale)
    }

    @Test func goesStaleAfterThreeWeeksAndCountsDownToIt() throws {
        let context = try makeContext()
        let log = weights([(7, 3.8 * kg)], in: context)

        let freshDay = birth.addingTimeInterval((7 + 20) * 24 * 3600)
        let fresh = try #require(GrowthProjector.project(weights: log, profile: profile(), now: freshDay, calendar: utc))
        #expect(!fresh.isStale)
        #expect(GrowthProjector.daysUntilFreshWeight(fresh) == 1)

        let staleDay = birth.addingTimeInterval((7 + 22) * 24 * 3600)
        let stale = try #require(GrowthProjector.project(weights: log, profile: profile(), now: staleDay, calendar: utc))
        #expect(stale.isStale)
        #expect(GrowthProjector.daysUntilFreshWeight(stale) == nil)
    }

    @Test func withoutSexThereIsNoProjection() throws {
        let context = try makeContext()
        let log = weights([(14, 4.2 * kg)], in: context)
        let now = birth.addingTimeInterval(20 * 24 * 3600)

        #expect(GrowthProjector.project(weights: log, profile: profile(sex: .unspecified), now: now, calendar: utc) == nil)
        #expect(GrowthProjector.project(weights: [], profile: profile(), now: now, calendar: utc) == nil)
    }

    @Test func pretermBabyIsPlottedAtCorrectedAge() throws {
        let context = try makeContext()
        // Born six weeks early: the due date is six weeks after the birthday.
        let due = birth.addingTimeInterval(42 * 24 * 3600)
        let preterm = profile(dueDate: due)
        #expect(preterm.isPreterm)

        // Weighed at ten weeks of life, i.e. four weeks corrected, at exactly
        // the median for four weeks. Corrected age should therefore read 50th.
        let medianAt4wCorrected = try #require(GrowthStandard.grams(percentile: 50, ageDays: 28, sex: .male))
        let log = weights([(70, medianAt4wCorrected)], in: context)
        let now = birth.addingTimeInterval(70 * 24 * 3600)

        let corrected = try #require(GrowthProjector.project(weights: log, profile: preterm, now: now, calendar: utc))
        let actualAge = try #require(GrowthProjector.project(weights: log, profile: profile(), now: now, calendar: utc))

        // A perfectly average four-week-old, plotted at ten weeks against term
        // standards, falls below WHO's 3rd-centile "low weight-for-age" line.
        // Turning a 50th-percentile baby into a clinical concern is exactly
        // what the due date is here to prevent.
        #expect(abs(corrected.anchorPercentile - 50) < 0.01)
        #expect(actualAge.anchorPercentile < 3)
    }

    @Test func beforeTheDueDateTheTermStandardsDoNotApply() throws {
        let context = try makeContext()
        let due = birth.addingTimeInterval(42 * 24 * 3600)
        let log = weights([(7, 2.2 * kg)], in: context)
        // A week old, still five weeks before the due date: corrected age is
        // negative, so there's no honest percentile to give.
        let now = birth.addingTimeInterval(7 * 24 * 3600)
        #expect(GrowthProjector.project(weights: log, profile: profile(dueDate: due), now: now, calendar: utc) == nil)
    }

    @Test func driftReportsTheMoveBetweenWeighIns() throws {
        let context = try makeContext()
        // 50th at two weeks, then 50th again at six weeks: no drift.
        let median2w = try #require(GrowthStandard.grams(percentile: 50, ageDays: 14, sex: .male))
        let median6w = try #require(GrowthStandard.grams(percentile: 50, ageDays: 42, sex: .male))
        let steady = weights([(42, median6w), (14, median2w)], in: context)

        let noDrift = try #require(GrowthProjector.drift(weights: steady, profile: profile()))
        #expect(abs(noDrift.deltaPercentile) < 0.01)
        #expect(abs(noDrift.deltaZ) < 0.001)
        #expect(!noDrift.hasFallenAChannel)
    }

    @Test func fallingAFullChannelIsFlagged() throws {
        let context = try makeContext()
        // 50th at two weeks, down to the 15th at six weeks - roughly a full
        // channel, which is what a pediatrician should hear about.
        let p50 = try #require(GrowthStandard.grams(percentile: 50, ageDays: 14, sex: .male))
        let p15 = try #require(GrowthStandard.grams(percentile: 15, ageDays: 42, sex: .male))
        let dropping = weights([(42, p15), (14, p50)], in: context)

        let drift = try #require(GrowthProjector.drift(weights: dropping, profile: profile()))
        #expect(drift.deltaPercentile < 0)
        #expect(drift.hasFallenAChannel)

        // A small wobble is not a channel drop.
        let p45 = try #require(GrowthStandard.grams(percentile: 45, ageDays: 42, sex: .male))
        let wobble = weights([(42, p45), (14, p50)], in: context)
        let small = try #require(GrowthProjector.drift(weights: wobble, profile: profile()))
        #expect(!small.hasFallenAChannel)
    }

    @Test func driftNeedsTwoWeighInsAndAKnownSex() throws {
        let context = try makeContext()
        let one = weights([(14, 4.2 * kg)], in: context)
        #expect(GrowthProjector.drift(weights: one, profile: profile()) == nil)

        let two = weights([(42, 5.0 * kg), (14, 4.2 * kg)], in: context)
        #expect(GrowthProjector.drift(weights: two, profile: profile(sex: .unspecified)) == nil)
        #expect(GrowthProjector.drift(weights: two, profile: profile()) != nil)
    }

    @Test func percentileOrdinalsReadCorrectly() {
        #expect(GrowthProjector.ordinal(percentile: 1) == "1st")
        #expect(GrowthProjector.ordinal(percentile: 2) == "2nd")
        #expect(GrowthProjector.ordinal(percentile: 3) == "3rd")
        #expect(GrowthProjector.ordinal(percentile: 4) == "4th")
        #expect(GrowthProjector.ordinal(percentile: 11) == "11th")
        #expect(GrowthProjector.ordinal(percentile: 12) == "12th")
        #expect(GrowthProjector.ordinal(percentile: 13) == "13th")
        #expect(GrowthProjector.ordinal(percentile: 21) == "21st")
        #expect(GrowthProjector.ordinal(percentile: 48.6) == "49th")
        // Clamped, because "0th" and "100th" are not things to tell a parent.
        #expect(GrowthProjector.ordinal(percentile: 0.2) == "1st")
        #expect(GrowthProjector.ordinal(percentile: 99.9) == "99th")
    }
}
