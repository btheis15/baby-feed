import Foundation
import SwiftData
import Testing
@testable import BabyFeed

struct CareNoteTests {
    private let now = Date(timeIntervalSince1970: 1_700_000_000)

    private var utc: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }

    private func makeContext() throws -> ModelContext {
        let container = try ModelContainer(
            for: CareNote.self, FeedEntry.self, WeightEntry.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        return ModelContext(container)
    }

    @Test func severityOnlyAppliesToKindsWhereItMeansSomething() {
        #expect(CareNoteKind.breathing.usesSeverity)
        #expect(CareNoteKind.crying.usesSeverity)
        #expect(CareNoteKind.rash.usesSeverity)
        // "How bad was the stool" isn't a scale anyone uses.
        #expect(!CareNoteKind.stool.usesSeverity)
        #expect(!CareNoteKind.temperature.usesSeverity)
        #expect(!CareNoteKind.other.usesSeverity)
    }

    @Test func everyKindHasATitleIconAndPlaceholder() {
        for kind in CareNoteKind.allCases {
            #expect(!kind.title.isEmpty)
            #expect(!kind.systemImage.isEmpty)
            // The placeholder is what stops people staring at an empty box.
            #expect(!kind.placeholder.isEmpty, "\(kind.rawValue) has no placeholder")
        }
    }

    @Test func softDeleteQueuesForUploadAndHidesTheNote() throws {
        let context = try makeContext()
        let note = CareNote(date: now, kind: .breathing, note: "snuffly")
        context.insert(note)
        #expect(note.isActive)

        note.softDelete()
        #expect(!note.isActive)
        #expect(note.deletedAt != nil)
        #expect(note.needsUpload)
        #expect([note].active(for: nil).isEmpty)
    }

    @Test func activeFilterRespectsTheBaby() throws {
        let context = try makeContext()
        let mine = UUID()
        let theirs = UUID()
        let a = CareNote(babyID: mine, date: now, kind: .crying, note: "an hour")
        let b = CareNote(babyID: theirs, date: now, kind: .crying, note: "not mine")
        context.insert(a)
        context.insert(b)

        #expect([a, b].active(for: mine).count == 1)
        #expect([a, b].active(for: mine).first === a)
        #expect([a, b].active(for: nil).count == 2)
    }

    /// The whole reason notes exist: they have to reach the report.
    @Test func notesInTheWindowReachTheReportAndTheSharedText() throws {
        let context = try makeContext()
        let profile = BabyProfile(name: "Nora", birthDate: now.addingTimeInterval(-20 * 24 * 3600))

        let recent = CareNote(
            date: now.addingTimeInterval(-2 * 24 * 3600),
            kind: .breathing,
            note: "sounded snuffly after the 3pm bottle",
            severity: .moderate
        )
        let old = CareNote(
            date: now.addingTimeInterval(-30 * 24 * 3600),
            kind: .crying,
            note: "long crying spell, well outside the window"
        )
        context.insert(recent)
        context.insert(old)

        let report = DaySummaryGenerator.report(
            entries: [],
            weights: [],
            careNotes: [recent, old],
            days: 7,
            unit: .ounces,
            weightUnit: .poundsOunces,
            profile: profile,
            calendar: utc,
            now: now
        )

        #expect(report.hasNotes)
        #expect(report.notes.count == 1, "the 30-day-old note is outside a 7-day window")
        let note = try #require(report.notes.first)
        #expect(note.kindTitle == "Breathing")
        #expect(note.severityTitle == "Moderate")
        #expect(note.text.contains("snuffly"))

        // And it must survive into the text that actually gets shared.
        let text = DaySummaryGenerator.plainText(from: report)
        #expect(text.contains("Notes"))
        #expect(text.contains("snuffly"))
        #expect(text.contains("moderate"))
        #expect(!text.contains("well outside the window"))
    }

    @Test func deletedNotesStayOutOfTheReport() throws {
        let context = try makeContext()
        let note = CareNote(date: now, kind: .rash, note: "red cheeks")
        context.insert(note)
        note.softDelete()

        let report = DaySummaryGenerator.report(
            entries: [],
            weights: [],
            careNotes: [note],
            days: 7,
            unit: .ounces,
            weightUnit: .poundsOunces,
            profile: BabyProfile(name: "Nora", birthDate: now),
            calendar: utc,
            now: now
        )
        #expect(!report.hasNotes)
        #expect(!DaySummaryGenerator.plainText(from: report).contains("red cheeks"))
    }

    @Test func aReportWithNoNotesSaysNothingAboutThem() throws {
        let report = DaySummaryGenerator.report(
            entries: [],
            weights: [],
            days: 7,
            unit: .ounces,
            weightUnit: .poundsOunces,
            profile: BabyProfile(name: "Nora", birthDate: now),
            calendar: utc,
            now: now
        )
        #expect(!report.hasNotes)
        #expect(!DaySummaryGenerator.plainText(from: report).contains("Notes"))
    }
}

/// Sex and the due date now live on the Baby model, so they can reach other
/// caregivers instead of sitting in one phone's UserDefaults.
struct BabyProfileMirrorTests {
    private let birth = Date(timeIntervalSince1970: 1_700_000_000)

    @Test func theModelRoundTripsThroughTheProfile() {
        // Six weeks early, i.e. 34 weeks' gestation.
        let due = birth.addingTimeInterval(42 * 24 * 3600)
        let baby = Baby(name: "Nora", birthDate: birth, sex: .female, dueDate: due)

        #expect(baby.sex == .female)
        #expect(baby.sexRaw == BabySex.female.rawValue)

        let profile = baby.profile
        #expect(profile.name == "Nora")
        #expect(profile.birthDate == birth)
        #expect(profile.sex == .female)
        #expect(profile.dueDate == due)
        #expect(profile.isPreterm)
    }

    /// Three weeks early is 37 weeks, which is term – so the threshold is
    /// deliberately "more than" three weeks, not "at least".
    @Test func exactlyThreeWeeksEarlyCountsAsTerm() {
        let threeWeeks = Baby(name: "Sam", birthDate: birth, dueDate: birth.addingTimeInterval(21 * 24 * 3600))
        #expect(!threeWeeks.profile.isPreterm)

        let justOver = Baby(name: "Sam", birthDate: birth, dueDate: birth.addingTimeInterval(22 * 24 * 3600))
        #expect(justOver.profile.isPreterm)
    }

    @Test func aBabyWithoutThemIsUnspecifiedAndTerm() {
        let baby = Baby(name: "Sam", birthDate: birth)
        #expect(baby.sex == .unspecified)
        #expect(baby.dueDate == nil)
        #expect(!baby.profile.isPreterm)
        // Which is what gates the percentiles.
        #expect(baby.profile.sex.known == nil)
    }

    @Test func settingSexThroughTheConvenienceUpdatesTheRawValue() {
        let baby = Baby(name: "Sam", birthDate: birth)
        baby.sex = .male
        #expect(baby.sexRaw == "male")
        #expect(baby.profile.sex == .male)
    }
}
