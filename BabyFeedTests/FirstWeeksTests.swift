import Foundation
import Testing
@testable import BabyFeed

/// "Getting enough?" in the first six weeks: every expectation at each
/// day-of-life boundary, and the one red flag only when it's earned.
struct EnoughSummaryTests {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)
    private func ago(_ hours: Double) -> Date { now.addingTimeInterval(-hours * 3600) }

    @Test func wetDiaperExpectationsFollowTheFirstWeek() {
        #expect(IntakeGuidance.expectedWet(ageDays: 0) == 1...2)
        #expect(IntakeGuidance.expectedWet(ageDays: 1) == 1...2)
        #expect(IntakeGuidance.expectedWet(ageDays: 2) == 2...3)
        #expect(IntakeGuidance.expectedWet(ageDays: 4) == 2...3)
        #expect(IntakeGuidance.expectedWet(ageDays: 5) == 5...6)
        #expect(IntakeGuidance.expectedWet(ageDays: 40) == 5...6)
        #expect(IntakeGuidance.expectedWet(ageDays: -1) == nil)
    }

    @Test func stoolsAreOnlyCountedFromDayFive() {
        #expect(IntakeGuidance.expectedDirty(ageDays: 4) == nil)
        #expect(IntakeGuidance.expectedDirty(ageDays: 5) == 3...4)
    }

    /// The sentence and the numbers come from the same place.
    @Test func theSentenceMatchesTheNumbers() {
        #expect(IntakeGuidance.diaperExpectation(ageDays: 1) == "1–2 wet diapers a day is normal this early.")
        #expect(IntakeGuidance.diaperExpectation(ageDays: 3) == "About 2–3 wet diapers a day while your milk comes in.")
        #expect(IntakeGuidance.diaperExpectation(ageDays: 10) == "At least 5–6 wet diapers a day, and 3–4 stools.")
    }

    @Test func countsTheLastTwentyFourHoursAgainstTheAge() {
        let diapers = [
            DiaperEntry(time: ago(1), kind: .wet),
            DiaperEntry(time: ago(3), kind: .both),
            DiaperEntry(time: ago(5), kind: .dirty),
            DiaperEntry(time: ago(30), kind: .wet),   // outside the window
        ]
        let feeds = (0..<9).map { FeedEntry(startTime: ago(Double($0) * 2.5), kind: .formula, amountML: 60) }
        let summary = EnoughSummary(diapers: diapers, feeds: feeds, ageDays: 3, now: now)

        #expect(summary.wet == .init(count: 2, expected: 2...3))
        #expect(summary.wet.meetsExpectation)
        #expect(summary.dirty.expected == nil, "no stool count before day 5")
        #expect(!summary.dirty.meetsExpectation)
        #expect(summary.feeds == .init(count: 9, expected: 8...12))
        #expect(summary.feeds.meetsExpectation)
    }

    @Test func aLowCountIsJustANumber() {
        let summary = EnoughSummary(diapers: [DiaperEntry(time: ago(1), kind: .wet)], feeds: [], ageDays: 8, now: now)
        #expect(summary.wet == .init(count: 1, expected: 5...6))
        #expect(!summary.wet.meetsExpectation)
        #expect(summary.noWetSince == nil, "one low day is not the red flag")
    }

    @Test func theRedFlagOnlyWhenTheLogKeptGoing() {
        let lastWet = DiaperEntry(time: ago(9), kind: .wet)
        let feedSince = FeedEntry(startTime: ago(2), kind: .nursing, durationMinutes: 15)
        let dirtySince = DiaperEntry(time: ago(1), kind: .dirty)

        // Nine hours dry, and feeds are still being logged: say so.
        #expect(EnoughSummary.noWetSince(diapers: [lastWet], feeds: [feedSince], now: now) == lastWet.time)
        #expect(EnoughSummary.noWetSince(diapers: [lastWet, dirtySince], feeds: [], now: now) == lastWet.time)
        // Nothing logged since: that's a gap in the log, not a reading.
        #expect(EnoughSummary.noWetSince(diapers: [lastWet], feeds: [], now: now) == nil)
        // Seven hours: under the guidance's eight.
        let recent = DiaperEntry(time: ago(7), kind: .wet)
        #expect(EnoughSummary.noWetSince(diapers: [recent], feeds: [feedSince], now: now) == nil)
        // Days ago: the family stopped logging diapers, the baby didn't stop.
        let old = DiaperEntry(time: ago(30), kind: .wet)
        #expect(EnoughSummary.noWetSince(diapers: [old], feeds: [feedSince], now: now) == nil)
        // "Both" counts as wet.
        let both = DiaperEntry(time: ago(3), kind: .both)
        #expect(EnoughSummary.noWetSince(diapers: [lastWet, both], feeds: [feedSince], now: now) == nil)
    }

    @Test func showsForTheFirstSixWeeks() {
        #expect(EnoughSummary.shows(ageDays: 0))
        #expect(EnoughSummary.shows(ageDays: 41))
        #expect(!EnoughSummary.shows(ageDays: 42))
        #expect(!EnoughSummary.shows(ageDays: nil))
    }
}

struct BirthWeightStatusTests {
    private let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/New_York")!
        return calendar
    }()

    private var birthday: Date {
        calendar.date(from: DateComponents(year: 2026, month: 9, day: 1, hour: 6))!
    }

    private func onDay(_ day: Int, _ grams: Double) -> WeightEntry {
        WeightEntry(date: calendar.date(byAdding: .day, value: day, to: birthday)!, grams: grams)
    }

    @Test func sevenPercentDownIsShownWithTheUsualRange() {
        let status = BirthWeightStatus(weights: [onDay(0, 3400), onDay(3, 3162)], birthDate: birthday, calendar: calendar)
        #expect(status == .below(birthGrams: 3400, latestGrams: 3162, onDay: 3))
        let line = status.line(weightUnit: .kilograms)
        #expect(line?.contains("−7%") == true)
        #expect(line?.contains("day 3") == true)
        #expect(line?.contains("10–14") == true)
    }

    @Test func backToBirthWeightOnDayEleven() {
        let weights = [onDay(0, 3400), onDay(4, 3200), onDay(11, 3420), onDay(13, 3390)]
        let status = BirthWeightStatus(weights: weights, birthDate: birthday, calendar: calendar)
        #expect(status == .regained(onDay: 11), "the milestone stays reached")
        #expect(status.line(weightUnit: .kilograms) == "Back to birth weight ✓ on day 11")
        #expect(status.isRegained)
    }

    @Test func notBackByDayFifteenIsTheRedFlag() {
        let status = BirthWeightStatus(weights: [onDay(0, 3400), onDay(15, 3300)], birthDate: birthday, calendar: calendar)
        #expect(status == .notRegained(birthGrams: 3400, latestGrams: 3300, onDay: 15))
    }

    /// An old weigh-in doesn't say anything about now: a day-5 reading on day
    /// 15 is still just "below", not the flag.
    @Test func theFlagNeedsARecentWeighIn() {
        let status = BirthWeightStatus(weights: [onDay(0, 3400), onDay(5, 3250)], birthDate: birthday, calendar: calendar)
        #expect(status == .below(birthGrams: 3400, latestGrams: 3250, onDay: 5))
    }

    @Test func noBirthWeightMeansNoLine() {
        // The first weigh-in is a week in: not a birth weight.
        let status = BirthWeightStatus(weights: [onDay(7, 3300)], birthDate: birthday, calendar: calendar)
        #expect(status == .noBirthWeight)
        #expect(status.line(weightUnit: .kilograms) == nil)
        #expect(BirthWeightStatus(weights: [onDay(0, 3400)], birthDate: nil, calendar: calendar) == .noBirthWeight)
    }

    @Test func aBirthWeightOnTheDayAfterCounts() {
        let status = BirthWeightStatus(weights: [onDay(1, 3400)], birthDate: birthday, calendar: calendar)
        #expect(status == .birthOnly(grams: 3400))
    }

    @Test func percentagesRoundAndUseARealMinus() {
        #expect(BirthWeightStatus.percentText(-0.0735) == "−7%")
        #expect(BirthWeightStatus.percentText(0.01) == "+1%")
    }
}

struct NextSideTests {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    @Test func theOtherSideFromLastTime() {
        let left = FeedEntry(startTime: now.addingTimeInterval(-3600), kind: .nursing, durationMinutes: 15, side: .left)
        #expect(NextSide.suggestion(after: [left]) == .right)
        let right = FeedEntry(startTime: now, kind: .nursing, durationMinutes: 10, side: .right)
        #expect(NextSide.suggestion(after: [left, right]) == .left, "the latest nursing feed decides")
    }

    @Test func bothOrNoSideSuggestsNothing() {
        #expect(NextSide.suggestion(after: [FeedEntry(startTime: now, kind: .nursing, side: .both)]) == nil)
        #expect(NextSide.suggestion(after: [FeedEntry(startTime: now, kind: .nursing)]) == nil)
        #expect(NextSide.suggestion(after: []) == nil)
    }

    @Test func bottlesInBetweenDontCount() {
        let left = FeedEntry(startTime: now.addingTimeInterval(-7200), kind: .nursing, durationMinutes: 15, side: .left)
        let bottle = FeedEntry(startTime: now, kind: .formula, amountML: 90)
        #expect(NextSide.suggestion(after: [bottle, left]) == .right)
        #expect(NextSide.last(in: [bottle, left]) == .left)
    }
}

struct NursingSessionTests {
    private let start = Date(timeIntervalSince1970: 1_800_000_000)
    private func at(_ minutes: Double) -> Date { start.addingTimeInterval(minutes * 60) }

    @Test func minutesOnlyAndNeverZero() {
        let session = NursingSession(startedAt: start, side: .left)
        #expect(session.minutes(at: at(0.2)) == 1)
        #expect(session.minutes(at: at(12.9)) == 12)
    }

    @Test func switchingSidesMakesItBoth() {
        var session = NursingSession(startedAt: start, side: .left)
        session.switchSide(at: at(8))
        #expect(session.side == .right)
        #expect(session.minutesOnCurrentSide(at: at(14)) == 6)
        #expect(session.feedSide == .both)

        let feed = session.feed(endingAt: at(20), babyID: nil, loggedByName: "Annette")
        #expect(feed.kind == .nursing)
        #expect(feed.startTime == start)
        #expect(feed.durationMinutes == 20)
        #expect(feed.side == .both)
        #expect(feed.loggedByName == "Annette")
    }

    @Test func oneSideStaysThatSide() {
        let session = NursingSession(startedAt: start, side: .right)
        #expect(session.feed(endingAt: at(15), babyID: nil, loggedByName: "").side == .right)
    }

    @Test func anHourInItAsksStillNursing() {
        let session = NursingSession(startedAt: start, side: .left)
        #expect(!session.isProbablyForgotten(at: at(59)))
        #expect(session.isProbablyForgotten(at: at(60)))
    }

    @Test func survivesTheAppBeingKilled() throws {
        let defaults = try #require(UserDefaults(suiteName: "NursingSessionTests-\(UUID().uuidString)"))
        var session = NursingSession(startedAt: start, side: .left)
        session.switchSide(at: at(5))
        session.save(to: defaults)
        #expect(NursingSession.load(from: defaults) == session)
        NursingSession.clear(from: defaults)
        #expect(NursingSession.load(from: defaults) == nil)
    }
}

struct NightHoursTests {
    private let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/New_York")!
        return calendar
    }()

    private func time(_ hour: Int, _ minute: Int = 0, day: Int = 28) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 9, day: day, hour: hour, minute: minute))!
    }

    @Test func eightToSevenAcrossMidnight() {
        let night = NightHours.standard
        #expect(!night.contains(time(19, 59), calendar: calendar))
        #expect(night.contains(time(20), calendar: calendar))
        #expect(night.contains(time(23, 30), calendar: calendar))
        #expect(night.contains(time(3), calendar: calendar))
        #expect(night.contains(time(6, 59), calendar: calendar))
        #expect(!night.contains(time(7), calendar: calendar))
        #expect(!night.contains(time(12), calendar: calendar))
    }

    @Test func aWindowInsideOneDay() {
        let nap = NightHours(startMinutes: 13 * 60, endMinutes: 15 * 60)
        #expect(nap.contains(time(14), calendar: calendar))
        #expect(!nap.contains(time(15), calendar: calendar))
        #expect(!NightHours(startMinutes: 60, endMinutes: 60).contains(time(1), calendar: calendar))
    }

    @Test func theNextBoundaryIsWhenToLookAgain() {
        let night = NightHours.standard
        #expect(night.nextBoundary(after: time(12), calendar: calendar) == time(20))
        #expect(night.nextBoundary(after: time(21), calendar: calendar) == time(7, day: 29))
        #expect(night.nextBoundary(after: time(3), calendar: calendar) == time(7))
    }
}
