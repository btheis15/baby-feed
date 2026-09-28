import Foundation
import Testing
@testable import BabyFeed

/// "Export everything" and the pediatrician summary: the two places the log
/// leaves the app, where a stray comma or a missing day would be copied into
/// someone else's records.
struct CareLogExportTests {
    private let baby = UUID()
    private let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/New_York")!
        return calendar
    }()

    private var now: Date {
        calendar.date(from: DateComponents(year: 2026, month: 9, day: 28, hour: 12))!
    }

    private let profile = BabyProfile(name: "Nora", birthDate: nil, sex: .unspecified, dueDate: nil)

    // MARK: CSV

    @Test func fieldsAreQuotedOnlyWhenTheyHaveTo() {
        #expect(CareLogCSV.field("plain") == "plain")
        #expect(CareLogCSV.field("") == "")
        #expect(CareLogCSV.field("spit up, twice") == "\"spit up, twice\"")
        #expect(CareLogCSV.field("the \"good\" bottle") == "\"the \"\"good\"\" bottle\"")
        #expect(CareLogCSV.field("line one\nline two") == "\"line one\nline two\"")
    }

    @Test func everyKindGetsOneRowNewestFirstInTheLogsTimeZone() {
        let items = TimelineBuilder.items(TimelineSources(
            feeds: [FeedEntry(babyID: baby, startTime: now.addingTimeInterval(-3600), kind: .formula, amountML: 90,
                              note: "fussy, then fine", loggedByName: "Annette")],
            diapers: [DiaperEntry(babyID: baby, time: now.addingTimeInterval(-7200), kind: .both)],
            notes: [CareNote(babyID: baby, date: now.addingTimeInterval(-26 * 3600), kind: .rash,
                             note: "red patch, left cheek", severity: .mild)]
        ), babyID: baby)

        let lines = CareLogCSV.csv(items, unit: .milliliters, weightUnit: .kilograms, calendar: calendar)
            .components(separatedBy: "\n")
        #expect(lines.count == 4)
        #expect(lines[0] == CareLogCSV.header)
        #expect(lines[1] == "2026-09-28,11:00,feed,formula,\(VolumeUnit.milliliters.format(milliliters: 90)),\"fussy, then fine\",Annette")
        #expect(lines[2] == "2026-09-28,10:00,diaper,both,,,")
        #expect(lines[3] == "2026-09-27,10:00,note,rash,Mild,\"red patch, left cheek\",")
    }

    // MARK: The pediatrician summary

    /// A day where only diapers got logged still gets its row, and says
    /// nothing about feeds rather than "0 feeds".
    @Test func aDayWithOnlyDiapersGetsItsOwnRow() {
        let yesterday = now.addingTimeInterval(-24 * 3600)
        let report = DaySummaryGenerator.report(
            entries: [FeedEntry(babyID: baby, startTime: now.addingTimeInterval(-600), kind: .formula, amountML: 90)],
            weights: [],
            diapers: [
                DiaperEntry(babyID: baby, time: yesterday, kind: .wet),
                DiaperEntry(babyID: baby, time: yesterday.addingTimeInterval(3600), kind: .dirty),
            ],
            days: 7, unit: .milliliters, weightUnit: .kilograms, profile: profile,
            calendar: calendar, now: now
        )

        #expect(report.days.count == 2)
        let diaperDay = report.days[1]
        #expect(calendar.isDate(diaperDay.id, inSameDayAs: yesterday))
        #expect(diaperDay.feedCount == 0)
        #expect(diaperDay.wet == 1 && diaperDay.dirty == 1)
        #expect(DaySummaryGenerator.dayDetail(diaperDay) == "diapers 1 wet · 1 dirty")
        #expect(!DaySummaryGenerator.plainText(from: report).contains("0 feeds"))
        #expect(report.averagesFootnote == "Feeds averaged over the 1 day with feeds logged, diapers over the 1 day with diapers logged.")
    }

    /// A stretch where nobody logged a bottle still has diaper numbers worth
    /// taking to the appointment.
    @Test func diaperAveragesDoNotNeedAnyFeeds() {
        let report = DaySummaryGenerator.report(
            entries: [],
            weights: [],
            diapers: [
                DiaperEntry(babyID: baby, time: now.addingTimeInterval(-3600), kind: .wet),
                DiaperEntry(babyID: baby, time: now.addingTimeInterval(-7200), kind: .wet),
                DiaperEntry(babyID: baby, time: now.addingTimeInterval(-30 * 3600), kind: .both),
            ],
            days: 7, unit: .milliliters, weightUnit: .kilograms, profile: profile,
            calendar: calendar, now: now
        )

        #expect(!report.hasFeeds)
        #expect(report.days.count == 2)
        #expect(report.averageItems.contains { $0.id == "wetDiapers" && $0.value == "1.5" })
        #expect(report.averageItems.contains { $0.id == "dirtyDiapers" && $0.value == "0.5" })
        let text = DaySummaryGenerator.plainText(from: report)
        #expect(text.contains("No feeds logged in this period."))
        #expect(text.contains("wet diapers 1.5"))
        #expect(text.contains("Today: diapers 2 wet"))
        #expect(report.averagesFootnote == "Averaged over the 2 days with diapers logged.")
    }
}
