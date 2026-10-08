import Foundation
import Testing
@testable import BabyFeed

struct FineDaysTests {
    private var utc: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }

    private let start = Date(timeIntervalSince1970: 1_700_006_400) // a UTC midnight

    private func day(_ n: Int, hour: Int = 10) -> Date {
        start.addingTimeInterval(Double(n) * 86_400 + Double(hour) * 3600)
    }

    private func midnight(_ n: Int) -> Date { utc.startOfDay(for: day(n)) }

    private func intake(_ n: Int, feeds: Int, ml: Double) -> CareCharts.IntakeDay {
        CareCharts.IntakeDay(day: midnight(n), feeds: feeds, bottles: feeds, nursing: 0, volumeML: ml,
                             nursingMinutes: 0, targetML: nil)
    }

    @Test func unloggedDaysAreTheOnesWithNoFeedOrDiaperBeforeToday() {
        let feeds = [FeedEntry(startTime: day(0), kind: .formula, amountML: 90)]
        let diapers = [DiaperEntry(time: day(2), kind: .wet)]
        let days = FineDays.unlogged(feeds: feeds, diapers: diapers, from: day(0), today: day(4), calendar: utc)
        // Days 1 and 3, newest first; day 4 is today and not over yet.
        #expect(days == [midnight(3), midnight(1)])
    }

    @Test func aMarkedDayIsEstimatedFromTheDaysAroundIt() {
        let logged = [intake(0, feeds: 8, ml: 600), intake(2, feeds: 6, ml: 400)]
        let filled = FineDays.filled(logged, fine: [midnight(1)])
        #expect(filled.count == 3)
        let estimate = filled[1]
        #expect(estimate.isEstimated)
        #expect(estimate.feeds == 7)
        #expect(estimate.volumeML == 500)
        // The logged days are untouched.
        #expect(!filled[0].isEstimated && !filled[2].isEstimated)
    }

    @Test func aMarkNeverReplacesALoggedDayOrInventsOneFromNothing() {
        let logged = [intake(0, feeds: 8, ml: 600)]
        #expect(FineDays.filled(logged, fine: [midnight(0)]).count == 1)
        #expect(FineDays.filled(logged, fine: [midnight(30)]).count == 1)
        #expect(FineDays.filled([CareCharts.IntakeDay](), fine: [midnight(1)]).isEmpty)
    }

    @Test func marksAreReadFromAllFineNotesOnly() {
        let mark = FineDays.newMark(on: midnight(3), babyID: nil, loggedByName: "Brian", calendar: utc)
        let other = CareNote(date: day(4), kind: .rash, note: "red")
        #expect(FineDays.marked([mark, other], calendar: utc) == [midnight(3)])
        #expect(utc.component(.hour, from: mark.date) == 12)
        #expect([mark, other].writtenNotes.count == 1)
    }

    @Test func theSentenceSaysEstimatesAreLeftOutOfTheAverage() {
        #expect(FineDays.sentenceSuffix(estimatedDays: 0).isEmpty)
        #expect(FineDays.sentenceSuffix(estimatedDays: 2).contains("2 days marked fine"))
    }

    @Test func theMarkerIsNotOfferedAsAKindOfNote() {
        #expect(!CareNoteKind.pickable.contains(.allFine))
        #expect(CareNoteKind.pickable.count == CareNoteKind.allCases.count - 1)
    }
}
