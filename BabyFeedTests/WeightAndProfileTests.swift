import Foundation
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
