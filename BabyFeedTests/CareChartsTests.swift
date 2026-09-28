import Foundation
import Testing
@testable import BabyFeed

/// The charts draw the same numbers the rest of the app states, and their
/// sentences come from those numbers too. Pinned here so a chart can never
/// show a total the Timeline or the summary disagrees with.
struct CareChartsTests {
    private let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/New_York")!
        return calendar
    }()

    private var now: Date { calendar.date(from: DateComponents(year: 2026, month: 9, day: 28, hour: 12))! }

    private func day(_ daysAgo: Int, hour: Int) -> Date {
        let start = calendar.date(byAdding: .day, value: -daysAgo, to: calendar.startOfDay(for: now))!
        return calendar.date(bySettingHour: hour, minute: 0, second: 0, of: start)!
    }

    private var profile: BabyProfile {
        BabyProfile(name: "Nora", birthDate: day(20, hour: 6), sex: .female, dueDate: nil)
    }

    private var range: DateInterval { ChartRange.twoWeeks.interval(now: now, lastVisit: nil, calendar: calendar) }

    @Test func theSeriesAddUpToTheSameTotalsAsEverywhereElse() {
        let feeds = [
            FeedEntry(startTime: day(0, hour: 2), kind: .formula, amountML: 90),
            FeedEntry(startTime: day(0, hour: 6), kind: .nursing, durationMinutes: 15),
            FeedEntry(startTime: day(1, hour: 9), kind: .breastMilk, amountML: 60),
            FeedEntry(startTime: day(20, hour: 9), kind: .formula, amountML: 90),  // outside the 2 weeks
        ]
        let intake = CareCharts.intake(feeds: feeds, weights: [], profile: profile, style: .formula, feedsPerDay: 0,
                                       range: range, calendar: calendar)
        let inRange = FeedSummary(Array(feeds.prefix(3)))
        #expect(intake.reduce(0) { $0 + $1.feeds } == inRange.feedCount)
        #expect(intake.reduce(0) { $0 + $1.volumeML } == inRange.totalML)
        #expect(intake.reduce(0) { $0 + $1.nursingMinutes } == inRange.nursingMinutes)
        #expect(intake.map(\.day) == [calendar.startOfDay(for: day(1, hour: 0)), calendar.startOfDay(for: now)],
                "oldest first, for a chart that reads left to right")

        let diapers = [
            DiaperEntry(time: day(0, hour: 3), kind: .both),
            DiaperEntry(time: day(0, hour: 5), kind: .wet),
            DiaperEntry(time: day(3, hour: 5), kind: .dirty),
        ]
        let diaperDays = CareCharts.diapers(diapers, range: range, calendar: calendar)
        let tally = DiaperTally(diapers)
        #expect(diaperDays.reduce(0) { $0 + $1.wet } == tally.wet)
        #expect(diaperDays.reduce(0) { $0 + $1.dirty } == tally.dirty)
    }

    /// A day nobody logged is a gap in the chart, not a zero that reads as a
    /// day the baby didn't eat.
    @Test func missingDaysAreGapsNotZeros() {
        let feeds = [0, 5, 9].map { FeedEntry(startTime: day($0, hour: 10), kind: .formula, amountML: 90) }
        let intake = CareCharts.intake(feeds: feeds, weights: [], profile: profile, style: .formula, feedsPerDay: 0,
                                       range: range, calendar: calendar)
        #expect(intake.count == 3)
        #expect(intake.allSatisfy { $0.feeds > 0 })
        #expect(CareCharts.diapers([], range: range, calendar: calendar).isEmpty)
    }

    @Test func eachDaysTargetIsTheTargetAtTheEndOfThatDay() {
        let weights = [WeightEntry(date: day(20, hour: 8), grams: 3300), WeightEntry(date: day(5, hour: 10), grams: 3600)]
        let feeds = [8, 3].map { FeedEntry(startTime: day($0, hour: 10), kind: .formula, amountML: 90) }
        let intake = CareCharts.intake(feeds: feeds, weights: weights, profile: profile, style: .formula, feedsPerDay: 0,
                                       range: range, calendar: calendar)
        for entry in intake {
            let endOfDay = calendar.date(byAdding: .day, value: 1, to: entry.day)!.addingTimeInterval(-1)
            let known = weights.filter { $0.date <= endOfDay }.sorted { $0.date > $1.date }
            let expected = FeedingGuidance.currentTarget(weights: known, profile: profile, style: .formula,
                                                         feedsPerDay: 0, now: endOfDay, calendar: calendar).target?.targetML
            #expect(entry.targetML == expected)
        }
        // The later weigh-in only counts from the day it was made.
        #expect(intake[0].targetML != intake[1].targetML)
    }

    @Test func thePercentileBandsAreTheWHOStandard() throws {
        let chart = CareCharts.weight(weights: [WeightEntry(date: day(20, hour: 8), grams: 3300)], profile: profile,
                                      now: now, calendar: calendar)
        #expect(!chart.outer.isEmpty && chart.outer.count == chart.inner.count && chart.inner.count == chart.median.count)
        for (index, band) in chart.outer.enumerated() {
            let age = try #require(profile.growthAgeDays(on: band.date))
            #expect(band.low == GrowthStandard.grams(percentile: 3, ageDays: age, sex: .female))
            #expect(band.high == GrowthStandard.grams(percentile: 97, ageDays: age, sex: .female))
            #expect(chart.inner[index].low == GrowthStandard.grams(percentile: 15, ageDays: age, sex: .female))
            #expect(chart.inner[index].high == GrowthStandard.grams(percentile: 85, ageDays: age, sex: .female))
            #expect(chart.median[index].grams == GrowthStandard.grams(percentile: 50, ageDays: age, sex: .female))
        }
        #expect(chart.birthGrams == 3300, "still the first weeks, and not back yet: the birth line shows")
    }

    @Test func noBandsWithoutSex() {
        let unknown = BabyProfile(name: "Nora", birthDate: day(20, hour: 6), sex: .unspecified, dueDate: nil)
        let chart = CareCharts.weight(weights: [WeightEntry(date: day(3, hour: 8), grams: 3500)], profile: unknown,
                                      now: now, calendar: calendar)
        #expect(chart.outer.isEmpty && chart.median.isEmpty && chart.projection.isEmpty)
        #expect(chart.weighIns.count == 1)
    }

    @Test func theSentencesStateTheNumbers() {
        let feeds = [0, 0, 1, 1].map { FeedEntry(startTime: day($0, hour: 8 + $0), kind: .formula, amountML: 100) }
        let intake = CareCharts.intake(feeds: feeds, weights: [], profile: profile, style: .formula, feedsPerDay: 0,
                                       range: range, calendar: calendar)
        let sentence = CareCharts.intakeSentence(intake, unit: .milliliters, name: "Nora", range: .twoWeeks)
        #expect(sentence.hasPrefix("Nora averaged 2.0 feeds and \(VolumeUnit.milliliters.format(milliliters: 200)) a day over the last 2 weeks"))

        let diaperDays = [CareCharts.DiaperDay(day: day(0, hour: 0), wet: 6, dirty: 3),
                          CareCharts.DiaperDay(day: day(1, hour: 0), wet: 5, dirty: 2)]
        #expect(CareCharts.diaperSentence(diaperDays, range: .twoWeeks) == "5.5 wet and 2.5 dirty diapers a day, on the 2 days they were logged.")
        #expect(CareCharts.intakeSentence([], unit: .ounces, name: "Nora", range: .month) == "No feeds logged over the last month.")
    }

    /// Nursing isn't measured, so with it in the mix the volume is what the
    /// bottles added up to, and there's no target line for it to fall short of.
    @Test func mixedFeedingSaysBottlesAndDrawsNoTarget() {
        let feeds = [
            FeedEntry(startTime: day(0, hour: 2), kind: .formula, amountML: 90),
            FeedEntry(startTime: day(0, hour: 5), kind: .nursing, durationMinutes: 20),
            FeedEntry(startTime: day(1, hour: 9), kind: .formula, amountML: 120),
        ]
        let weights = [WeightEntry(date: day(20, hour: 8), grams: 3300)]
        let intake = CareCharts.intake(feeds: feeds, weights: weights, profile: profile, style: .formula, feedsPerDay: 0,
                                       range: range, calendar: calendar)
        #expect(intake.contains { $0.targetML != nil })
        #expect(CareCharts.showsVolume(intake))
        #expect(!CareCharts.showsTarget(intake))
        let sentence = CareCharts.intakeSentence(intake, unit: .milliliters, name: "Nora", range: .twoWeeks)
        #expect(sentence == "Nora averaged 1.5 feeds a day over the last 2 weeks, with \(VolumeUnit.milliliters.format(milliliters: 105)) from bottles and about 10 min of nursing.")

        let bottlesOnly = CareCharts.intake(feeds: [feeds[0], feeds[2]], weights: weights, profile: profile, style: .formula,
                                            feedsPerDay: 0, range: range, calendar: calendar)
        #expect(CareCharts.showsTarget(bottlesOnly))
        #expect(CareCharts.intakeSentence(bottlesOnly, unit: .milliliters, name: "Nora", range: .twoWeeks).contains("against a target of about"))
    }

    /// A baby fed only at the breast gets feed counts, never a volume of zero.
    @Test func nursingOnlyIsCountedInFeeds() {
        let feeds = [0, 0, 1, 1].map { FeedEntry(startTime: day($0, hour: 3 + $0 * 2), kind: .nursing, durationMinutes: 15) }
        let intake = CareCharts.intake(feeds: feeds, weights: [], profile: profile, style: .breastMilk, feedsPerDay: 0,
                                       range: range, calendar: calendar)
        #expect(!CareCharts.showsVolume(intake))
        #expect(CareCharts.intakeSentence(intake, unit: .ounces, name: "Nora", range: .twoWeeks)
                == "Nora averaged 2.0 feeds a day over the last 2 weeks, with about 30 min of nursing.")
        #expect(CareCharts.minutesText(65) == "1 hr 5 min")
        #expect(CareCharts.minutesText(120) == "2 hr")
    }

    @Test func theOverviewCountsWhatHappened() {
        let ongoing = HealthConcern(uuid: UUID(), title: "Red left eye", kind: .eye, startedAt: day(3, hour: 7))
        let cleared = HealthConcern(uuid: UUID(), title: "Stuffy nose", kind: .cough, startedAt: day(12, hour: 7))
        cleared.resolvedAt = day(8, hour: 7)
        let old = HealthConcern(uuid: UUID(), title: "Hiccups", kind: .other, startedAt: day(40, hour: 7))
        old.resolvedAt = day(39, hour: 7)
        let overview = CareCharts.overview(
            concerns: [ongoing, cleared, old],
            doses: [MedicationDose(medicationName: "Vitamin D", time: day(1, hour: 8))],
            visits: [DoctorVisit(date: day(5, hour: 10))],
            feedDays: [], diaperDays: [], range: range, now: now)
        #expect(overview.concerns.map(\.title) == ["Red left eye", "Stuffy nose"])
        #expect(CareCharts.overviewSentence(overview, range: .twoWeeks)
                == "1 concern ongoing, 1 that cleared up, 1 dose and 1 visit over the last 2 weeks.")
    }

    @Test func sinceTheLastVisitStartsThatDay() {
        let visit = day(9, hour: 15)
        let interval = ChartRange.sinceLastVisit.interval(now: now, lastVisit: visit, calendar: calendar)
        #expect(interval.start == calendar.startOfDay(for: visit))
        #expect(ChartRange.sinceLastVisit.interval(now: now, lastVisit: nil, calendar: calendar) == range)
        // With no visit yet it is 2 weeks, and the sentences say "the last 2 weeks".
        #expect(ChartRange.sinceLastVisit.effective(lastVisit: nil) == .twoWeeks)
        #expect(ChartRange.sinceLastVisit.effective(lastVisit: visit) == .sinceLastVisit)
        #expect(ChartRange.month.effective(lastVisit: nil) == .month)
    }

    /// Three months of axis for a three-week-old would be mostly empty.
    @Test func nothingStartsBeforeBirth() {
        let birth = day(20, hour: 6)
        let interval = ChartRange.threeMonths.interval(now: now, lastVisit: nil, birthDate: birth, calendar: calendar)
        #expect(interval.start == calendar.startOfDay(for: birth))
        #expect(interval.end == calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: now)))
        #expect(ChartRange.twoWeeks.interval(now: now, lastVisit: nil, birthDate: birth, calendar: calendar) == range,
                "a range that starts after the birth is untouched")
    }

    /// The weight axis runs from the day of birth to the end of today, and the
    /// curves reach both ends; without them it starts at the first weigh-in.
    @Test func theWeightAxisRunsFromBirthToTheEndOfToday() throws {
        let weights = [WeightEntry(date: day(12, hour: 8), grams: 3300), WeightEntry(date: day(2, hour: 8), grams: 3700)]
        let endOfToday = try #require(calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: now)))
        let chart = CareCharts.weight(weights: weights, profile: profile, now: now, calendar: calendar)
        let domain = try #require(chart.domain)
        #expect(domain.lowerBound == calendar.startOfDay(for: day(20, hour: 6)))
        #expect(domain.upperBound == endOfToday)
        #expect(chart.outer.first?.date == day(20, hour: 6), "from the moment of birth")
        #expect(chart.outer.last?.date == domain.upperBound)

        let unknown = BabyProfile(name: "Nora", birthDate: day(20, hour: 6), sex: .unspecified, dueDate: nil)
        let plain = CareCharts.weight(weights: weights, profile: unknown, now: now, calendar: calendar)
        #expect(plain.domain == calendar.startOfDay(for: day(12, hour: 8))...endOfToday)
    }
}
