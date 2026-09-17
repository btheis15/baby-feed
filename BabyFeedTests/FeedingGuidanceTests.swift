import Foundation
import Testing
@testable import BabyFeed

struct FeedingGuidanceTests {
    private let mlPerOunce = 29.5735
    private let gramsPerPound = 453.59237

    @Test func formulaRuleIsTwoAndAHalfOuncesPerPound() throws {
        let target = try #require(FeedingGuidance.dailyTarget(weightGrams: 8 * gramsPerPound, ageDays: 30, style: .formula, feedsPerDay: 8))
        #expect(abs(target.targetML - 20 * mlPerOunce) < 0.5)
        #expect(abs(target.perFeedML - 2.5 * mlPerOunce) < 0.5)
        #expect(target.feedsPerDay == 8)
        #expect(target.rangeML == nil)
    }

    @Test func formulaRuleCapsAtThirtyTwoOunces() throws {
        let target = try #require(FeedingGuidance.dailyTarget(weightGrams: 15 * gramsPerPound, ageDays: 120, style: .formula))
        #expect(abs(target.targetML - 32 * mlPerOunce) < 0.5)
        #expect(target.basis.contains("capped"))
    }

    @Test func firstTwoWeeksAlsoShowAgeRange() throws {
        let target = try #require(FeedingGuidance.dailyTarget(weightGrams: 7 * gramsPerPound, ageDays: 5, style: .formula))
        #expect(target.rangeML != nil)
    }

    @Test func breastfedBabiesPlateauAfterFirstMonth() throws {
        let target = try #require(FeedingGuidance.dailyTarget(weightGrams: 12 * gramsPerPound, ageDays: 45, style: .breastMilk))
        #expect(abs(target.targetML - 25 * mlPerOunce) < 0.5)
        #expect(target.rangeML == FeedingGuidance.breastMilkDailyRangeML)
    }

    @Test func breastfedNewbornsUseWeightRuleBeforePlateau() throws {
        let target = try #require(FeedingGuidance.dailyTarget(weightGrams: 8 * gramsPerPound, ageDays: 20, style: .breastMilk))
        #expect(abs(target.targetML - 20 * mlPerOunce) < 0.5)
    }

    @Test func ageOnlyFallsBackToTypicalRange() throws {
        let target = try #require(FeedingGuidance.dailyTarget(weightGrams: nil, ageDays: 45, style: .formula))
        let range = try #require(target.rangeML)
        #expect(range.contains(target.targetML))
        #expect(target.feedsPerDay == FeedingGuidance.ageBand(forAgeDays: 45).typicalFeedsPerDay)
    }

    @Test func nothingToGoOnGivesNoTarget() {
        #expect(FeedingGuidance.dailyTarget(weightGrams: nil, ageDays: nil, style: .formula) == nil)
    }

    @Test func zeroFeedsPerDayMeansTypicalForAge() throws {
        let target = try #require(FeedingGuidance.dailyTarget(weightGrams: 8 * gramsPerPound, ageDays: 10, style: .formula, feedsPerDay: 0))
        #expect(target.feedsPerDay == FeedingGuidance.ageBand(forAgeDays: 10).typicalFeedsPerDay)
    }

    @Test func ageBandsCoverEveryAge() {
        #expect(FeedingGuidance.ageBand(forAgeDays: 0).title == "First few days")
        #expect(FeedingGuidance.ageBand(forAgeDays: 10).title == "First 2 weeks")
        #expect(FeedingGuidance.ageBand(forAgeDays: 20).title == "2–4 weeks")
        #expect(FeedingGuidance.ageBand(forAgeDays: 45).title == "1–2 months")
        #expect(FeedingGuidance.ageBand(forAgeDays: 100).title == "2–4 months")
        #expect(FeedingGuidance.ageBand(forAgeDays: 150).title == "4–6 months")
        #expect(FeedingGuidance.ageBand(forAgeDays: 400).title == "6+ months")
    }

    @Test func suggestedIntervalGrowsWithAge() {
        #expect(FeedingGuidance.suggestedIntervalHours(ageDays: nil) == 3)
        #expect(FeedingGuidance.suggestedIntervalHours(ageDays: 2) < FeedingGuidance.suggestedIntervalHours(ageDays: 150))
    }
}
