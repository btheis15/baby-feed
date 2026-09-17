import Foundation
import SwiftData
import Testing
@testable import BabyFeed

struct WeightUnitTests {
    private let us = Locale(identifier: "en_US")

    @Test func poundsAndOuncesRoundTrip() {
        let grams = WeightUnit.grams(pounds: 7, ounces: 12)
        let split = WeightUnit.poundsAndOunces(grams: grams)
        #expect(split.pounds == 7)
        #expect(split.ounces == 12)
        #expect(WeightUnit.poundsOunces.format(grams: grams) == "7 lb 12 oz")
    }

    @Test func wholePoundsDropTheOunces() {
        #expect(WeightUnit.poundsOunces.format(grams: WeightUnit.grams(pounds: 8, ounces: 0)) == "8 lb")
    }

    @Test func kilogramsFormatWithTwoDecimals() {
        #expect(WeightUnit.kilograms.format(grams: 3520, locale: us) == "3.52 kg")
    }

    @Test func gainFormatting() {
        #expect(WeightUnit.kilograms.formatGain(gramsPerWeek: 170.4) == "+170 g/week")
        #expect(WeightUnit.poundsOunces.formatGain(gramsPerWeek: -56.7).hasPrefix("−2 oz"))
    }

    @Test func changeFormattingCarriesTheSign() {
        #expect(WeightUnit.kilograms.formatChange(grams: 113.4) == "+113 g")
        #expect(WeightUnit.kilograms.formatChange(grams: -113.4) == "−113 g")
        #expect(WeightUnit.poundsOunces.formatChange(grams: WeightUnit.gramsPerOunce * 4) == "+4 oz")
        #expect(WeightUnit.poundsOunces.formatChange(grams: 0) == "+0 oz")
    }
}

struct WeightStatsTests {
    private var utc: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }

    private let now = Date(timeIntervalSince1970: 1_700_000_000)

    private func makeContext() throws -> ModelContext {
        let container = try ModelContainer(
            for: WeightEntry.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        return ModelContext(container)
    }

    /// Weights newest first, as the views' reverse-sorted query supplies them.
    private func weights(_ specs: [(daysAgo: Double, grams: Double)], in context: ModelContext) -> [WeightEntry] {
        let entries = specs.map { spec in
            WeightEntry(date: now.addingTimeInterval(-spec.daysAgo * 24 * 3600), grams: spec.grams)
        }
        entries.forEach { context.insert($0) }
        return entries
    }

    @Test func lastChangeUsesTheTwoMostRecentWeighIns() throws {
        let context = try makeContext()
        let log = weights([(0, 3500), (7, 3300), (21, 3000)], in: context)

        let change = try #require(WeightStats.lastChange(log, calendar: utc))
        #expect(change.grams == 200)
        #expect(change.days == 7)
        // 200 g over exactly one week.
        let rate = try #require(change.gramsPerWeek)
        #expect(abs(rate - 200) < 0.001)
    }

    @Test func lastChangeWithholdsARateOverTooShortASpan() throws {
        let context = try makeContext()
        // Two weigh-ins the same day: the step is real, the weekly rate is not.
        let log = weights([(0, 3520), (0.5, 3500)], in: context)

        let change = try #require(WeightStats.lastChange(log, calendar: utc))
        #expect(change.grams == 20)
        #expect(change.gramsPerWeek == nil)
    }

    @Test func lastChangeIsNegativeWhenBabyLosesWeight() throws {
        let context = try makeContext()
        let log = weights([(0, 3300), (7, 3500)], in: context)

        let change = try #require(WeightStats.lastChange(log, calendar: utc))
        #expect(change.grams == -200)
        #expect(try #require(change.gramsPerWeek) < 0)
    }

    @Test func overallRateSpansTheWholeLog() throws {
        let context = try makeContext()
        let log = weights([(0, 3600), (7, 3300), (14, 3000)], in: context)

        // 600 g over two weeks is 300 g a week, even though the last step was 300.
        let rate = try #require(WeightStats.overallGramsPerWeek(log))
        #expect(abs(rate - 300) < 0.001)
        #expect(WeightStats.changeSinceFirst(log) == 600)
    }

    @Test func singleWeighInHasNoTrendYet() throws {
        let context = try makeContext()
        let log = weights([(0, 3500)], in: context)

        #expect(WeightStats.lastChange(log, calendar: utc) == nil)
        #expect(WeightStats.changeSinceFirst(log) == nil)
        #expect(WeightStats.overallGramsPerWeek(log) == nil)
        #expect(WeightStats.lastChange([], calendar: utc) == nil)
    }
}

struct BabyProfileTests {
    private var utc: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }

    private let now = Date(timeIntervalSince1970: 1_700_000_000)

    @Test func ageInDaysCountsCalendarDays() {
        let profile = BabyProfile(name: "Sam", birthDate: now.addingTimeInterval(-3 * 24 * 3600))
        #expect(profile.ageInDays(on: now, calendar: utc) == 3)
        #expect(profile.ageText(on: now, calendar: utc) == "3 days old")
    }

    @Test func ageTextSwitchesToWeeksThenMonths() {
        let twentyDays = BabyProfile(name: "", birthDate: now.addingTimeInterval(-20 * 24 * 3600))
        #expect(twentyDays.ageText(on: now, calendar: utc) == "2w 6d old")

        let fourteenDays = BabyProfile(name: "", birthDate: now.addingTimeInterval(-14 * 24 * 3600))
        #expect(fourteenDays.ageText(on: now, calendar: utc) == "2 weeks old")

        let hundredDays = BabyProfile(name: "", birthDate: now.addingTimeInterval(-100 * 24 * 3600))
        #expect(hundredDays.ageText(on: now, calendar: utc)?.hasSuffix("months old") == true)
    }

    @Test func missingBirthdayMeansNoAge() {
        let profile = BabyProfile(name: "", birthDate: nil)
        #expect(profile.ageInDays() == nil)
        #expect(profile.ageText() == nil)
        #expect(profile.displayName == "Baby")
    }
}

struct ElapsedTextTests {
    @Test func sharedHelperMatchesFeedStats() {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let start = now.addingTimeInterval(-(3 * 3600 + 7 * 60))
        #expect(ElapsedText.compact(since: start, now: now) == "3h 7m")
        #expect(FeedStats.elapsedText(since: start, now: now) == ElapsedText.compact(since: start, now: now))
    }
}
