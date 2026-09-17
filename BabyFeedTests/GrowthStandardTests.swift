import Foundation
import Testing
@testable import BabyFeed

struct GrowthStandardTests {
    private let kg = GrowthStandard.gramsPerKilogram

    /// The important one. WHO prints both the LMS parameters and the resulting
    /// centile columns; if our Box-Cox maths and the transcribed L, M, S are
    /// both right, recomputing the centiles must reproduce WHO's printed
    /// numbers. WHO rounds them to one decimal place in kg, so agreement within
    /// 0.05 kg is exact agreement. A single mistyped digit anywhere in the
    /// table breaks this.
    @Test func reproducesEveryPrintedCentileInTheWHOTables() throws {
        var checked = 0
        for (sex, rows) in [(BabySex.male, WHOFixture.boys), (BabySex.female, WHOFixture.girls)] {
            for row in rows {
                for (centile, printed) in zip(WHOFixture.centiles, row.printed) {
                    let grams = try #require(GrowthStandard.grams(
                        percentile: centile,
                        ageDays: row.ageDays,
                        sex: sex
                    ))
                    let difference = abs(grams / kg - printed)
                    #expect(
                        difference <= 0.05,
                        """
                        \(sex) at \(row.ageDays) days, \(centile)th centile: \
                        computed \(grams / kg) kg, WHO prints \(printed) kg
                        """
                    )
                    checked += 1
                }
            }
        }
        // 35 ages × 11 centiles × 2 sexes.
        #expect(checked == 770)
    }

    @Test func medianWeightsMatchWHOAtBirth() throws {
        // WHO's published medians at birth.
        let boy = try #require(GrowthStandard.grams(percentile: 50, ageDays: 0, sex: .male))
        let girl = try #require(GrowthStandard.grams(percentile: 50, ageDays: 0, sex: .female))
        #expect(abs(boy / kg - 3.3464) < 0.0001)
        #expect(abs(girl / kg - 3.2322) < 0.0001)

        // A baby at the median is by definition the 50th percentile, z = 0.
        let z = try #require(GrowthStandard.zScore(grams: boy, ageDays: 0, sex: .male))
        #expect(abs(z) < 1e-9)
    }

    @Test func percentileAndWeightRoundTrip() throws {
        for centile in [3.0, 15, 25, 50, 75, 97] {
            for ageDays in [0.0, 17, 45.5, 91, 200, 500, 730] {
                let grams = try #require(GrowthStandard.grams(percentile: centile, ageDays: ageDays, sex: .female))
                let back = try #require(GrowthStandard.percentile(grams: grams, ageDays: ageDays, sex: .female))
                #expect(abs(back - centile) < 1e-6)
            }
        }
    }

    @Test func sameWeightSitsOnDifferentCentilesForBoysAndGirls() throws {
        // Girls are lighter at the median, so a given weight is a higher
        // percentile for a girl than for a boy.
        let grams = 4.0 * kg
        let girl = try #require(GrowthStandard.percentile(grams: grams, ageDays: 28, sex: .female))
        let boy = try #require(GrowthStandard.percentile(grams: grams, ageDays: 28, sex: .male))
        #expect(girl > boy)
    }

    @Test func percentilesRiseWithWeightAndFallWithAge() throws {
        let heavier = try #require(GrowthStandard.percentile(grams: 5.0 * kg, ageDays: 30, sex: .male))
        let lighter = try #require(GrowthStandard.percentile(grams: 4.0 * kg, ageDays: 30, sex: .male))
        #expect(heavier > lighter)

        // The same weight is a lower percentile as the baby gets older.
        let younger = try #require(GrowthStandard.percentile(grams: 5.0 * kg, ageDays: 30, sex: .male))
        let older = try #require(GrowthStandard.percentile(grams: 5.0 * kg, ageDays: 90, sex: .male))
        #expect(older < younger)
    }

    @Test func interpolatesBetweenTabulatedAges() throws {
        // Half a week past birth should land between the week 0 and week 1
        // medians, not snap to either.
        let birth = try #require(GrowthStandard.grams(percentile: 50, ageDays: 0, sex: .male))
        let week1 = try #require(GrowthStandard.grams(percentile: 50, ageDays: 7, sex: .male))
        let middle = try #require(GrowthStandard.grams(percentile: 50, ageDays: 3.5, sex: .male))
        #expect(middle > birth)
        #expect(middle < week1)
    }

    @Test func weeklyAndMonthlyTablesAgreeAtTheSeam() throws {
        // Week 13 (91 days) and month 3 (91.3125 days) are the same moment in
        // two different WHO tables; they must not disagree visibly.
        let week13 = try #require(GrowthStandard.grams(percentile: 50, ageDays: 91, sex: .male))
        let month3 = try #require(GrowthStandard.grams(percentile: 50, ageDays: 3 * WHOWeightForAge.daysPerMonth, sex: .male))
        #expect(abs(week13 - month3) / kg < 0.02)
    }

    @Test func refusesAgesOutsideTheStandard() {
        #expect(GrowthStandard.parameters(ageDays: -1, sex: .male) == nil)
        #expect(GrowthStandard.percentile(grams: 4000, ageDays: -0.5, sex: .male) == nil)
        // Past 24 months these tables stop applying.
        #expect(GrowthStandard.parameters(ageDays: WHOWeightForAge.maximumAgeDays + 1, sex: .male) == nil)
        #expect(GrowthStandard.parameters(ageDays: WHOWeightForAge.maximumAgeDays, sex: .male) != nil)
    }

    @Test func refusesNonsenseWeights() {
        #expect(GrowthStandard.zScore(grams: 0, ageDays: 10, sex: .male) == nil)
        #expect(GrowthStandard.zScore(grams: -500, ageDays: 10, sex: .male) == nil)
    }

    @Test func normalDistributionHelpersAreSane() {
        #expect(abs(GrowthStandard.normalCDF(0) - 0.5) < 1e-12)
        #expect(abs(GrowthStandard.normalCDF(1.959964) - 0.975) < 1e-6)
        #expect(abs(GrowthStandard.normalCDF(-1.959964) - 0.025) < 1e-6)

        #expect(abs(GrowthStandard.zScore(percentile: 50)) < 1e-9)
        #expect(abs(GrowthStandard.zScore(percentile: 97.5) - 1.959964) < 1e-6)
        #expect(abs(GrowthStandard.zScore(percentile: 2.5) + 1.959964) < 1e-6)
    }

    @Test func unspecifiedSexIsWhatGatesTheFeature() {
        #expect(BabySex.unspecified.known == nil)
        #expect(BabySex.male.known == .male)
        #expect(BabySex.female.known == .female)
    }
}
