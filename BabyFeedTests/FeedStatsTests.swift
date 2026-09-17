import Foundation
import SwiftData
import Testing
@testable import BabyFeed

struct FeedStatsTests {
    private let now = Date(timeIntervalSince1970: 1_700_000_000) // 2023-11-14 22:13:20 UTC

    private var utc: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }

    /// Model instances are created inside an in-memory container so SwiftData is happy.
    private func makeContext() throws -> ModelContext {
        let container = try ModelContainer(
            for: FeedEntry.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        return ModelContext(container)
    }

    @Test func elapsedTextIsCompact() {
        func elapsed(_ seconds: TimeInterval) -> String {
            FeedStats.elapsedText(since: now.addingTimeInterval(-seconds), now: now)
        }
        #expect(elapsed(30) == "Just now")
        #expect(elapsed(45 * 60) == "45m")
        #expect(elapsed(2 * 3600) == "2h")
        #expect(elapsed(2 * 3600 + 5 * 60) == "2h 5m")
        #expect(elapsed(26 * 3600) == "1d 2h")
        #expect(elapsed(48 * 3600) == "2d")
    }

    @Test func elapsedTextClampsFutureDates() {
        #expect(FeedStats.elapsedText(since: now.addingTimeInterval(600), now: now) == "Just now")
    }

    @Test func averageGapBetweenFeeds() throws {
        let context = try makeContext()
        let entries = [
            FeedEntry(startTime: now, kind: .formula, amountML: 60),
            FeedEntry(startTime: now.addingTimeInterval(-3 * 3600), kind: .formula, amountML: 60),
            FeedEntry(startTime: now.addingTimeInterval(-5 * 3600), kind: .nursing, durationMinutes: 10),
        ]
        entries.forEach { context.insert($0) }
        let gap = try #require(FeedStats.averageGapHours(entries))
        #expect(abs(gap - 2.5) < 0.001)
        #expect(FeedStats.averageGapHours([entries[0]]) == nil)
    }

    @Test func summaryKeepsBottlesAndNursingSeparate() throws {
        let context = try makeContext()
        let entries = [
            FeedEntry(startTime: now, kind: .formula, amountML: 60),
            FeedEntry(startTime: now, kind: .breastMilk, amountML: 90),
            FeedEntry(startTime: now, kind: .nursing, durationMinutes: 15, side: .left),
        ]
        entries.forEach { context.insert($0) }

        let summary = FeedSummary(entries)
        #expect(summary.feedCount == 3)
        #expect(summary.bottleCount == 2)
        #expect(summary.totalML == 150)
        #expect(summary.nursingCount == 1)
        #expect(summary.nursingMinutes == 15)
        #expect(summary.text(unit: .milliliters) == "3 feeds · 150 ml · 15 min nursing")
    }

    @Test func summaryOfSingleFeedUsesSingular() throws {
        let context = try makeContext()
        let entry = FeedEntry(startTime: now, kind: .formula, amountML: 60)
        context.insert(entry)
        #expect(FeedSummary([entry]).text(unit: .milliliters) == "1 feed · 60 ml")
    }

    @Test func windowKeepsOnlyRecentEntries() throws {
        let context = try makeContext()
        let recent = FeedEntry(startTime: now.addingTimeInterval(-23 * 3600), kind: .formula, amountML: 60)
        let old = FeedEntry(startTime: now.addingTimeInterval(-25 * 3600), kind: .formula, amountML: 60)
        context.insert(recent)
        context.insert(old)

        let kept = FeedStats.entries([recent, old], within: 24 * 3600, now: now)
        #expect(kept.count == 1)
        #expect(kept.first === recent)
    }

    @Test func groupsByDayNewestFirst() throws {
        let context = try makeContext()
        let dayOne = now
        let dayTwo = now.addingTimeInterval(24 * 3600)
        let entries = [
            FeedEntry(startTime: dayOne, kind: .formula, amountML: 60),
            FeedEntry(startTime: dayTwo, kind: .formula, amountML: 60),
            FeedEntry(startTime: dayTwo.addingTimeInterval(-3600), kind: .nursing, durationMinutes: 10),
        ]
        entries.forEach { context.insert($0) }

        let groups = FeedStats.groupByDay(entries, calendar: utc)
        #expect(groups.count == 2)
        #expect(groups[0].entries.count == 2)
        #expect(groups[0].entries[0].startTime == dayTwo)
        #expect(groups[1].entries.count == 1)
        #expect(groups[1].day == utc.startOfDay(for: dayOne))
    }

    @Test func dayTitlesAreRelative() {
        let calendar = utc
        #expect(FeedStats.dayTitle(for: now, calendar: calendar, now: now) == "Today")
        let yesterday = now.addingTimeInterval(-24 * 3600)
        #expect(FeedStats.dayTitle(for: yesterday, calendar: calendar, now: now) == "Yesterday")
        let lastWeek = now.addingTimeInterval(-7 * 24 * 3600)
        #expect(FeedStats.dayTitle(for: lastWeek, calendar: calendar, now: now) != "Today")
    }

    @Test func csvHasHeaderAndEscapesNotes() throws {
        let context = try makeContext()
        let entries = [
            FeedEntry(startTime: now, kind: .formula, amountML: 60, note: "said \"hi\""),
            FeedEntry(startTime: now.addingTimeInterval(-3600), kind: .nursing, durationMinutes: 12, side: .both),
        ]
        entries.forEach { context.insert($0) }

        let csv = FeedStats.csv(entries, unit: .milliliters, calendar: utc)
        let lines = csv.split(separator: "\n")
        #expect(lines.count == 3)
        #expect(lines[0] == "date,time,kind,amount,unit,duration_min,side,note")
        #expect(lines[1] == "2023-11-14,22:13,formula,60,ml,,,\"said \"\"hi\"\"\"")
        #expect(lines[2] == "2023-11-14,21:13,nursing,,,12,both,\"\"")
    }
}
