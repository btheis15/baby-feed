import Foundation
import SwiftData
import Testing
@testable import BabyFeed

/// The amount a bottle starts at follows what the caregiver actually gives,
/// once that's a habit rather than a coincidence.
struct LearnedAmountTests {
    private let now = Date(timeIntervalSince1970: 1_700_000_000)

    private func makeContext() throws -> ModelContext {
        let container = try ModelContainer(
            for: FeedEntry.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        return ModelContext(container)
    }

    /// Feeds newest first, `hoursAgo` back from `now`.
    private func feeds(
        _ specs: [(hoursAgo: Double, ml: Double?)],
        kind: FeedKind = .formula,
        in context: ModelContext
    ) -> [FeedEntry] {
        let entries = specs.map { spec in
            FeedEntry(
                startTime: now.addingTimeInterval(-spec.hoursAgo * 3600),
                kind: kind,
                amountML: spec.ml
            )
        }
        entries.forEach { context.insert($0) }
        return entries
    }

    @Test func medianHandlesOddAndEvenCounts() {
        #expect(FeedStats.median(of: [10, 20, 30]) == 20)
        #expect(FeedStats.median(of: [10, 20, 30, 40]) == 25)
        #expect(FeedStats.median(of: [5]) == 5)
        #expect(FeedStats.median(of: []) == nil)
        // Order shouldn't matter.
        #expect(FeedStats.median(of: [30, 10, 20]) == 20)
    }

    /// The scenario asked for: someone who consistently gives 20 ml.
    @Test func consistentTwentyBecomesTheTypicalAmount() throws {
        let context = try makeContext()
        let log = feeds([(1, 20), (4, 20), (7, 20), (10, 20), (13, 20)], in: context)

        let typical = try #require(FeedStats.typicalAmountML(log, kind: .formula))
        #expect(typical == 20)
    }

    /// A median, not a mean, so one huge bottle doesn't drag the default up.
    @Test func oneOutlierDoesNotMoveIt() throws {
        let context = try makeContext()
        let log = feeds([(1, 20), (4, 20), (7, 20), (10, 20), (13, 200)], in: context)

        let typical = try #require(FeedStats.typicalAmountML(log, kind: .formula))
        #expect(typical == 20, "the mean would be 56")
    }

    @Test func tooFewFeedsIsNotAHabitYet() throws {
        let context = try makeContext()
        // Three feeds is a coincidence; the default shouldn't start chasing it.
        let three = feeds([(1, 20), (4, 20), (7, 20)], in: context)
        #expect(FeedStats.typicalAmountML(three, kind: .formula) == nil)

        let four = feeds([(1, 20), (4, 20), (7, 20), (10, 20)], in: context)
        #expect(FeedStats.typicalAmountML(four, kind: .formula) == 20)
    }

    @Test func itFollowsTheCaregiverAsTheyChange() throws {
        let context = try makeContext()
        // Older feeds were small; the recent ones are bigger. With a window of
        // four, only the recent ones count.
        let log = feeds([(1, 90), (4, 90), (7, 90), (10, 90), (40, 20), (43, 20), (46, 20)], in: context)

        let typical = try #require(FeedStats.typicalAmountML(log, kind: .formula, recentCount: 4))
        #expect(typical == 90)
    }

    @Test func kindsAreKeptSeparateAndNursingIsIgnored() throws {
        let context = try makeContext()
        var log = feeds([(1, 30), (4, 30), (7, 30), (10, 30)], kind: .formula, in: context)
        log += feeds([(2, 90), (5, 90), (8, 90), (11, 90)], kind: .breastMilk, in: context)
        // Nursing has no volume, so it can't contribute.
        log += feeds([(3, nil), (6, nil), (9, nil), (12, nil)], kind: .nursing, in: context)

        #expect(FeedStats.typicalAmountML(log, kind: .formula) == 30)
        #expect(FeedStats.typicalAmountML(log, kind: .breastMilk) == 90)
        #expect(FeedStats.typicalAmountML(log, kind: .nursing) == nil)
    }

    @Test func deletedFeedsDoNotCount() throws {
        let context = try makeContext()
        let log = feeds([(1, 20), (4, 20), (7, 20), (10, 20), (13, 200)], in: context)
        // Soft-delete the four small ones; only the outlier is left, which is
        // below the minimum sample size.
        for entry in log.prefix(4) { entry.softDelete() }
        #expect(FeedStats.typicalAmountML(log, kind: .formula) == nil)
    }
}

/// Which of the four sources wins.
struct AmountSourceTests {
    private func makeDefaults(_ name: String) -> UserDefaults {
        let suite = "AmountSourceTests.\(name)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        return defaults
    }

    @Test func withNothingKnownItFallsBack() {
        let defaults = makeDefaults("fallback")
        let resolved = FeedDefaults.amount(for: .formula, unit: .ounces, defaults: defaults)
        #expect(resolved.source == .fallback)
        #expect(resolved.ml == VolumeUnit.ounces.toMilliliters(2))
    }

    @Test func theRecommendationIsUsedBeforeThereIsAHabit() {
        let defaults = makeDefaults("recommended")
        defaults.set(70.0, forKey: FeedDefaults.recommendedPerFeedKey)
        let resolved = FeedDefaults.amount(for: .formula, unit: .milliliters, defaults: defaults)
        #expect(resolved.source == .recommended)
        #expect(resolved.ml == 70)
    }

    /// The habit beats the rule of thumb: this baby beats a population average.
    @Test func theLearnedAmountBeatsTheRecommendation() {
        let defaults = makeDefaults("learned")
        defaults.set(70.0, forKey: FeedDefaults.recommendedPerFeedKey)
        defaults.set(20.0, forKey: FeedDefaults.typicalKey(for: .formula))

        let resolved = FeedDefaults.amount(for: .formula, unit: .milliliters, defaults: defaults)
        #expect(resolved.source == .learned)
        #expect(resolved.ml == 20)
    }

    @Test func aPinBeatsEverything() {
        let defaults = makeDefaults("pinned")
        defaults.set(70.0, forKey: FeedDefaults.recommendedPerFeedKey)
        defaults.set(20.0, forKey: FeedDefaults.typicalKey(for: .formula))
        FeedDefaults.setDefaultAmountML(150, for: .formula, defaults: defaults)

        let resolved = FeedDefaults.amount(for: .formula, unit: .milliliters, defaults: defaults)
        #expect(resolved.source == .pinned)
        #expect(resolved.ml == 150)
    }

    @Test func eachKindResolvesOnItsOwn() {
        let defaults = makeDefaults("perKind")
        defaults.set(70.0, forKey: FeedDefaults.recommendedPerFeedKey)
        defaults.set(20.0, forKey: FeedDefaults.typicalKey(for: .formula))

        #expect(FeedDefaults.amount(for: .formula, unit: .milliliters, defaults: defaults).source == .learned)
        #expect(FeedDefaults.amount(for: .breastMilk, unit: .milliliters, defaults: defaults).source == .recommended)
    }

    @Test func theLearnedAmountIsSnappedToTheUnitStep() {
        let defaults = makeDefaults("snap")
        // 23 ml isn't on the 10 ml grid.
        defaults.set(23.0, forKey: FeedDefaults.typicalKey(for: .formula))
        let resolved = FeedDefaults.amount(for: .formula, unit: .milliliters, defaults: defaults)
        #expect(resolved.ml == 20)
    }
}
