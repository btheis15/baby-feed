import Foundation
import Testing
@testable import BabyFeed

/// Diapers: the tally the day is judged by, the soft delete that has to reach
/// the other phone, and the DTO round-trip that carries it there.
struct DiaperEntryTests {
    @Test func bothCountsAsOneWetAndOneDirtyNotTwoChanges() {
        let tally = DiaperTally([
            DiaperEntry(kind: .wet),
            DiaperEntry(kind: .dirty),
            DiaperEntry(kind: .both),
        ])
        #expect(tally.wet == 2)
        #expect(tally.dirty == 2)
        #expect(tally.text == "2 wet · 2 dirty")
    }

    @Test func aDeletedDiaperLeavesTheTally() {
        let gone = DiaperEntry(kind: .wet)
        gone.softDelete()
        let tally = DiaperTally([gone, DiaperEntry(kind: .wet)])
        #expect(tally.wet == 1)
        #expect(gone.needsUpload, "the delete still has to reach the other phone")
        #expect(gone.deletedAt != nil)
    }

    @Test func onlyTheSideThatHappenedIsMentioned() {
        #expect(DiaperTally([DiaperEntry(kind: .wet)]).text == "1 wet")
        #expect(DiaperTally([DiaperEntry(kind: .dirty)]).text == "1 dirty")
        #expect(DiaperTally([]).text == "None yet")
    }

    @Test func activeFilterRespectsTheBaby() {
        let babyID = UUID()
        let otherID = UUID()
        let mine = DiaperEntry(babyID: babyID, kind: .wet)
        let theirs = DiaperEntry(babyID: otherID, kind: .wet)
        let deleted = DiaperEntry(babyID: babyID, kind: .dirty)
        deleted.softDelete()

        let visible = [mine, theirs, deleted].active(for: babyID)
        #expect(visible.count == 1)
        #expect(visible.first === mine)
    }

    @Test func theDTORoundTripsEverything() {
        let userID = UUID()
        let entry = DiaperEntry(babyID: UUID(), time: .now.addingTimeInterval(-3600),
                                kind: .both, note: "blowout", loggedByName: "Annette")

        let dto = DiaperDTO(entry: entry, userID: userID)
        #expect(dto != nil)
        #expect(dto?.kind == "both")
        #expect(dto?.loggedBy == userID)

        let restored = DiaperEntry(uuid: dto!.id, kind: .wet)
        dto!.apply(to: restored)
        #expect(restored.kind == .both)
        #expect(restored.time == entry.time)
        #expect(restored.note == "blowout")
        #expect(restored.loggedByName == "Annette")
        #expect(!restored.needsUpload, "a row that just arrived has nothing to upload")
    }

    @Test func aDiaperWithoutABabyMakesNoDTO() {
        // Mirrors the other row types: a row that belongs to no baby can't be
        // pushed, because the server files everything under one.
        #expect(DiaperDTO(entry: DiaperEntry(kind: .wet), userID: UUID()) == nil)
    }

    @Test func theReportCountsDiapersPerDay() {
        let calendar = Calendar.current
        let now = calendar.date(from: DateComponents(year: 2026, month: 9, day: 22, hour: 12))!
        let yesterday = calendar.date(byAdding: .day, value: -1, to: now)!
        let babyID = UUID()

        let feed = FeedEntry(babyID: babyID, startTime: now.addingTimeInterval(-600),
                             kind: .formula, amountML: 90)

        let diapers = [
            DiaperEntry(babyID: babyID, time: now.addingTimeInterval(-3600), kind: .wet),
            DiaperEntry(babyID: babyID, time: now.addingTimeInterval(-7200), kind: .both),
            DiaperEntry(babyID: babyID, time: yesterday, kind: .dirty),
        ]

        let report = DaySummaryGenerator.report(
            entries: [feed], weights: [], diapers: diapers, days: 7,
            unit: .milliliters, weightUnit: .kilograms,
            profile: BabyProfile(name: "Nora", birthDate: nil, sex: .unspecified, dueDate: nil),
            calendar: calendar, now: now)

        // Today: one wet + one both -> 2 wet, 1 dirty.
        let today = report.days.first { calendar.isDate($0.id, inSameDayAs: now) }
        #expect(today?.diaperText == "2 wet · 1 dirty")

        // Averaged over the two days that have diapers, and in the shared text.
        #expect(report.averageItems.contains { $0.id == "wetDiapers" && $0.value == "1.0" })
        #expect(report.averageItems.contains { $0.id == "dirtyDiapers" && $0.value == "1.0" })
        #expect(DaySummaryGenerator.plainText(from: report).contains("diapers 2 wet · 1 dirty"))
    }

    @Test func aWindowWithoutDiapersMentionsNoneAnywhere() {
        let feed = FeedEntry(kind: .formula)
        let report = DaySummaryGenerator.report(
            entries: [feed], weights: [], days: 7,
            unit: .milliliters, weightUnit: .kilograms,
            profile: BabyProfile(name: "Nora", birthDate: nil, sex: .unspecified, dueDate: nil))
        #expect(!report.averageItems.contains { $0.id == "wetDiapers" })
        #expect(!DaySummaryGenerator.plainText(from: report).contains("diaper"))
    }
}
