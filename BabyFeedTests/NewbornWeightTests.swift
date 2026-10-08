import Foundation
import Testing
@testable import BabyFeed

struct NewbornWeightTests {
    /// A UTC midnight, so "day 3.5" is the middle of the fourth calendar day of life.
    private let birth = Date(timeIntervalSince1970: 1_700_006_400)

    private var utc: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }

    private var profile: BabyProfile { BabyProfile(name: "Sam", birthDate: birth, sex: .female) }

    private func day(_ n: Double) -> Date { birth.addingTimeInterval(n * 86_400) }

    @Test func theDipBottomsOutOnDayThreeAndIsBackByDayTwelve() {
        #expect(NewbornWeight.factor(day: 0) == 1)
        #expect(abs(NewbornWeight.factor(day: 3) - (1 - NewbornWeight.typicalLoss)) < 0.0001)
        #expect(NewbornWeight.factor(day: 2) > NewbornWeight.factor(day: 3))
        #expect(NewbornWeight.factor(day: 8) > NewbornWeight.factor(day: 3))
        #expect(NewbornWeight.factor(day: 12) == 1)
        #expect(NewbornWeight.factor(day: 20) == 1)
    }

    @Test func aBirthWeightIsEstimatedLowerInTheFirstDays() throws {
        let birthWeight = WeightEntry(date: birth, grams: 3400)
        let projection = try #require(GrowthProjector.project(weights: [birthWeight], profile: profile,
                                                             now: day(3.5), calendar: utc))
        #expect(projection.followsNewbornDip)
        #expect(abs(projection.estimatedGrams - 3400 * (1 - NewbornWeight.typicalLoss)) < 1)
        // From no loss to the most that's still expected.
        #expect(abs(projection.rangeGrams.upperBound - 3400) < 1)
        #expect(abs(projection.rangeGrams.lowerBound - 3400 * (1 - NewbornWeight.largestExpectedLoss)) < 1)
        #expect(!projection.isStale)
    }

    @Test func aWeighInDuringTheDipRecoversTowardsBirthWeight() throws {
        // Weighed at day 3, 7% down; by day 12 the estimate is back where it started.
        let weighIn = WeightEntry(date: day(3.2), grams: 3162)
        let projection = try #require(GrowthProjector.project(weights: [weighIn], profile: profile,
                                                             now: day(12.5), calendar: utc))
        #expect(projection.followsNewbornDip)
        #expect(abs(projection.estimatedGrams - 3400) < 5)
    }

    @Test func afterTwoWeeksItFollowsThePercentileFromBirthWeightAtTwoWeeks() throws {
        let birthWeight = WeightEntry(date: birth, grams: 3400)
        let projection = try #require(GrowthProjector.project(weights: [birthWeight], profile: profile,
                                                             now: day(28), calendar: utc))
        #expect(!projection.followsNewbornDip)
        // Lower than carrying the birth weight's percentile from day 0, which
        // would assume two weeks of growth that the dip used up.
        let fromBirth = try #require(GrowthStandard.zScore(grams: 3400, ageDays: 0, sex: .female))
        let naive = try #require(GrowthStandard.grams(zScore: fromBirth, ageDays: 28, sex: .female))
        #expect(projection.estimatedGrams < naive)
        #expect(projection.estimatedGrams > 3400)
    }

    @Test func theDipIsCitedToAnAAPSource() {
        let source = FoodGuidance.sources.first { $0.id == NewbornWeight.sourceID }
        #expect(source?.organisation == "American Academy of Pediatrics")
    }

    @Test func theWeightChartDrawsTheDipADayAtATime() {
        let chart = CareCharts.weight(weights: [WeightEntry(date: birth, grams: 3400)], profile: profile,
                                      now: day(6.5), calendar: utc)
        #expect(chart.projection.count > 2)
        let lowest = chart.projection.map(\.grams).min() ?? 0
        #expect(lowest < 3400)
    }
}
