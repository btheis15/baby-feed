import Foundation
import Testing
@testable import BabyFeed

/// What counts as "a day" decides every header, total and "3 days ago" in the
/// app, so the awkward days are pinned: the ones daylight saving shortens or
/// stretches, and a log whose time zone is pinned away from the phone's.
struct DayGroupingTests {
    private func calendar(_ identifier: String) -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: identifier)!
        return calendar
    }

    private func date(_ calendar: Calendar, _ month: Int, _ day: Int, _ hour: Int, _ minute: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: month, day: day, hour: hour, minute: minute))!
    }

    @Test func newestDayFirstAndNewestFirstWithinADay() {
        let ny = calendar("America/New_York")
        let times = [date(ny, 9, 27, 8), date(ny, 9, 28, 1), date(ny, 9, 27, 22), date(ny, 9, 28, 9)]
        let groups = DayGrouping.group(times, calendar: ny) { $0 }
        #expect(groups.map(\.day) == [ny.startOfDay(for: times[1]), ny.startOfDay(for: times[0])])
        #expect(groups[0].items == [times[3], times[1]])
        #expect(groups[1].items == [times[2], times[0]])
    }

    /// 8 March 2026 in New York has 23 hours, 1 November has 25. Everything
    /// from just after midnight to just before the next one is the same day.
    @Test func daylightSavingDaysStayWhole() {
        let ny = calendar("America/New_York")
        let spring = [date(ny, 3, 8, 0, 30), date(ny, 3, 8, 23, 30)]
        #expect(DayGrouping.group(spring, calendar: ny) { $0 }.count == 1)
        let autumn = [date(ny, 11, 1, 0, 30), date(ny, 11, 1, 23, 30)]
        #expect(DayGrouping.group(autumn, calendar: ny) { $0 }.count == 1)
        // And the day after each is a day of its own.
        #expect(DayGrouping.group(spring + [date(ny, 3, 9, 0, 30)], calendar: ny) { $0 }.count == 2)
    }

    /// 11 p.m. in New York is already tomorrow in London. With the log pinned
    /// to New York, it belongs to the New York day, whatever the phone says.
    @Test func aPinnedTimeZoneDecidesTheDay() {
        let ny = calendar("America/New_York")
        let london = calendar("Europe/London")
        let lateEvening = date(ny, 9, 27, 23)
        let nextMorning = date(ny, 9, 28, 7)

        #expect(DayGrouping.group([lateEvening, nextMorning], calendar: ny) { $0 }.count == 2)
        #expect(DayGrouping.group([lateEvening, nextMorning], calendar: london) { $0 }.count == 1,
                "in London both are on the 28th")
    }

    /// The header must name the day its rows are from, even when the phone's
    /// own time zone would call that midnight the day before.
    @Test func dayTitlesAreWrittenInThePinnedTimeZone() {
        // Kiritimati is UTC+14, so its midnight is the previous day almost
        // everywhere else, including wherever these tests run.
        let far = calendar("Pacific/Kiritimati")
        let day = far.startOfDay(for: date(far, 9, 15, 12))
        let title = FeedStats.dayTitle(for: day, calendar: far, now: date(far, 9, 28, 12))
        #expect(title.contains("15"), "got \(title)")
        #expect(!title.contains("14"), "got \(title)")
    }
}

/// "How long ago was that?" is what a doctor asks, and it's asked in days.
struct RelativeAgeTests {
    private let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/New_York")!
        return calendar
    }()

    private var now: Date {
        calendar.date(from: DateComponents(year: 2026, month: 9, day: 28, hour: 9))!
    }

    private func daysAgo(_ days: Int, hour: Int = 20) -> Date {
        let day = calendar.date(byAdding: .day, value: -days, to: calendar.startOfDay(for: now))!
        return calendar.date(bySettingHour: hour, minute: 0, second: 0, of: day)!
    }

    @Test func countsCalendarDaysNotTwentyFourHourStretches() {
        // 8 p.m. yesterday is only 13 hours ago, and still "yesterday".
        #expect(RelativeAge.ago(daysAgo(1), now: now, calendar: calendar) == "Yesterday")
        #expect(RelativeAge.ago(daysAgo(0, hour: 1), now: now, calendar: calendar) == "Today")
    }

    @Test func theBoundaries() {
        let cases: [(Int, String)] = [
            (0, "Today"),
            (1, "Yesterday"),
            (2, "2 days ago"),
            (30, "30 days ago"),
            (31, "4 weeks ago"),
            (111, "15 weeks ago"),
            (112, "3 months ago"),
        ]
        for (days, expected) in cases {
            #expect(RelativeAge.ago(daysAgo(days, hour: 9), now: now, calendar: calendar) == expected, "\(days) days")
        }
    }

    /// Across the spring change, two calendar days are 47 hours; they're
    /// still two days.
    @Test func daylightSavingDoesNotLoseADay() {
        let before = calendar.date(from: DateComponents(year: 2026, month: 3, day: 7, hour: 12))!
        let after = calendar.date(from: DateComponents(year: 2026, month: 3, day: 9, hour: 11))!
        #expect(RelativeAge.days(from: before, to: after, calendar: calendar) == 2)
        #expect(RelativeAge.ago(before, now: after, calendar: calendar) == "2 days ago")
    }

    @Test func howLongSomethingLasted() {
        let start = daysAgo(5, hour: 8)
        #expect(RelativeAge.span(start: start, end: nil, now: now, calendar: calendar) == "ongoing · day 6")
        #expect(RelativeAge.span(start: start, end: daysAgo(1, hour: 8), now: now, calendar: calendar) == "lasted 4 days")
        #expect(RelativeAge.span(start: start, end: daysAgo(4, hour: 8), now: now, calendar: calendar) == "lasted 1 day")
        #expect(RelativeAge.span(start: start, end: start.addingTimeInterval(3 * 3600), now: now, calendar: calendar) == "lasted about 3 hours")
        #expect(RelativeAge.span(start: start, end: start.addingTimeInterval(40 * 60), now: now, calendar: calendar) == "lasted about an hour")
        #expect(RelativeAge.span(start: start, end: start.addingTimeInterval(20 * 60), now: now, calendar: calendar) == "lasted under an hour")
    }
}
