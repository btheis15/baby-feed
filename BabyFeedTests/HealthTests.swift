import Foundation
import Testing
@testable import BabyFeed

private let calendar: Calendar = {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "America/New_York")!
    return calendar
}()

/// Noon, Monday 28 September 2026, New York.
private let now = calendar.date(from: DateComponents(year: 2026, month: 9, day: 28, hour: 12))!
private func hoursAgo(_ hours: Double) -> Date { now.addingTimeInterval(-hours * 3600) }
private func daysAgo(_ days: Int, hour: Int = 9) -> Date {
    let day = calendar.date(byAdding: .day, value: -days, to: calendar.startOfDay(for: now))!
    return calendar.date(bySettingHour: hour, minute: 0, second: 0, of: day)!
}

struct ConcernStatsTests {
    @Test func countsTheFirstDayAsDayOne() {
        let concern = HealthConcern(title: "Red left eye", kind: .eye, startedAt: daysAgo(2))
        #expect(ConcernStats.dayNumber(concern, now: now, calendar: calendar) == 3)
        #expect(ConcernStats.statusText(concern, now: now, calendar: calendar) == "ongoing · day 3")
        #expect(ConcernStats.startedText(concern, now: now, calendar: calendar) == "since Sep 26 · 2 days ago")
    }

    @Test func aResolvedConcernSaysHowLongItLasted() {
        let concern = HealthConcern(title: "Stuffy nose", kind: .cough, startedAt: daysAgo(12))
        concern.resolvedAt = daysAgo(8)
        #expect(!concern.isOngoing)
        #expect(ConcernStats.statusText(concern, now: now, calendar: calendar) == "lasted 4 days")
        #expect(ConcernStats.dayNumber(concern, now: now, calendar: calendar) == 5)
    }

    @Test func aWeekWithoutAnUpdateAsksNeverAnswers() {
        let concern = HealthConcern(uuid: UUID(), title: "Rash", kind: .rash, startedAt: daysAgo(10))
        concern.updatedAt = daysAgo(10)
        #expect(ConcernStats.needsCheckIn(concern, notes: [], now: now, calendar: calendar))

        // An update on it resets the week.
        let update = CareNote(date: daysAgo(2), kind: .rash, note: "fading")
        update.concernID = concern.uuid
        #expect(!ConcernStats.needsCheckIn(concern, notes: [update], now: now, calendar: calendar))

        // A note about something else doesn't.
        let other = CareNote(date: daysAgo(1), kind: .sleep, note: "good night")
        #expect(ConcernStats.needsCheckIn(concern, notes: [other], now: now, calendar: calendar))

        // And it stays ongoing: nothing resolves by itself.
        #expect(concern.isOngoing)
    }

    /// Notes from before concerns existed are never shown as ongoing: a note
    /// is a moment, whatever its old resolvedAt says.
    @Test func existingNotesAreNeverOngoing() {
        let old = CareNote(date: daysAgo(5), kind: .rash, note: "red patch")
        let items = TimelineBuilder.items(TimelineSources(notes: [old]), babyID: nil)
        #expect(items.allSatisfy { if case .concern = $0 { false } else { true } })
    }
}

struct MedicationSafetyTests {
    private func medication(minHours: Double? = nil, maxPerDay: Int? = nil, schedule: MedicationSchedule = .asNeeded) -> Medication {
        Medication(uuid: UUID(), name: "Gas drops", schedule: schedule, timesPerDay: schedule == .daily ? 1 : nil,
                   minHoursBetween: minHours, maxDosesPer24h: maxPerDay, startDate: daysAgo(30))
    }

    private func dose(_ medication: Medication, _ time: Date, by name: String = "Brian") -> MedicationDose {
        MedicationDose(medicationID: medication.uuid, medicationName: medication.name, time: time, loggedByName: name)
    }

    @Test func tooSoonUpToTheMinimumGapAndNotAtIt() {
        let med = medication(minHours: 4)
        let justUnder = MedicationSafety.notices(for: med, doses: [dose(med, hoursAgo(3.99))], loggingAs: "Brian",
                                                 now: now, calendar: calendar)
        #expect(justUnder.contains { if case .tooSoon = $0 { true } else { false } })

        let exactly = MedicationSafety.notices(for: med, doses: [dose(med, hoursAgo(4))], loggingAs: "Brian",
                                               now: now, calendar: calendar)
        #expect(!exactly.contains { if case .tooSoon = $0 { true } else { false } })
    }

    @Test func theDailyLimitCountsTheLastTwentyFourHours() {
        let med = medication(maxPerDay: 3)
        let three = [hoursAgo(2), hoursAgo(8), hoursAgo(20)].map { dose(med, $0) }
        #expect(MedicationSafety.notices(for: med, doses: three, loggingAs: "Brian", now: now, calendar: calendar)
            .contains(.dailyMaxReached(count: 3, max: 3)))
        let oneFellOut = [hoursAgo(2), hoursAgo(8), hoursAgo(25)].map { dose(med, $0) }
        #expect(MedicationSafety.notices(for: med, doses: oneFellOut, loggingAs: "Brian", now: now, calendar: calendar)
            .isEmpty)
    }

    @Test func anotherCaregiversRecentDoseIsMentioned() {
        let med = medication(minHours: 4)
        let notices = MedicationSafety.notices(for: med, doses: [dose(med, hoursAgo(1), by: "Annette")],
                                               loggingAs: "Brian", now: now, calendar: calendar)
        #expect(notices.contains(.recentByOtherCaregiver(at: hoursAgo(1), by: "Annette")))
        // Your own isn't news.
        let mine = MedicationSafety.notices(for: med, doses: [dose(med, hoursAgo(1), by: "brian")],
                                            loggingAs: "Brian", now: now, calendar: calendar)
        #expect(!mine.contains { if case .recentByOtherCaregiver = $0 { true } else { false } })
    }

    @Test func aDailyOneAlreadyGivenToday() {
        let med = medication(schedule: .daily)
        let notices = MedicationSafety.notices(for: med, doses: [dose(med, daysAgo(0, hour: 8), by: "Annette")],
                                               loggingAs: "Brian", now: now, calendar: calendar)
        #expect(notices.contains(.alreadyGivenToday(at: daysAgo(0, hour: 8), by: "Annette")))
    }

    @Test func aFinishedCourseSaysSo() {
        let med = medication()
        med.endDate = daysAgo(3)
        #expect(MedicationSafety.notices(for: med, doses: [], loggingAs: "Brian", now: now, calendar: calendar)
            == [.courseEnded(on: daysAgo(3))])
    }

    /// The same dose logged on two phones while they were apart.
    @Test func twoDosesTooCloseAreFlagged() {
        let med = medication(minHours: 2)
        let first = dose(med, hoursAgo(3), by: "Annette")
        let second = dose(med, hoursAgo(2.5), by: "Brian")
        let later = dose(med, hoursAgo(0.1), by: "Brian")
        let flagged = MedicationSafety.possibleDuplicates(medications: [med], doses: [later, first, second])
        #expect(flagged.map(\.uuid) == [second.uuid])
    }

    @Test func dueFollowsTheSchedule() {
        let daily = medication(schedule: .daily)
        // Given at 8:10 yesterday: due at 8:10 today, and noon is past that.
        let yesterday = dose(daily, calendar.date(bySettingHour: 8, minute: 10, second: 0, of: daysAgo(1))!)
        #expect(MedicationStats.isDue(daily, doses: [yesterday], now: now, calendar: calendar))
        let today = dose(daily, daysAgo(0, hour: 8))
        #expect(!MedicationStats.isDue(daily, doses: [yesterday, today], now: now, calendar: calendar))

        let asNeeded = medication()
        #expect(MedicationStats.nextDue(asNeeded, doses: [], now: now, calendar: calendar) == nil)

        let everySix = Medication(uuid: UUID(), name: "Antibiotic", schedule: .everyNHours, intervalHours: 6, startDate: daysAgo(2))
        let last = dose(everySix, hoursAgo(5))
        #expect(MedicationStats.nextDue(everySix, doses: [last], now: now, calendar: calendar) == hoursAgo(-1))
    }
}

struct DoseDraftTests {
    @Test func neverInventsAnAmount() {
        #expect(DoseDraft.initial(for: nil) == DoseDraft(amount: nil, unit: .ml))
        let blank = Medication(name: "Vitamin D", kind: .supplement, doseUnit: .drop)
        #expect(DoseDraft.initial(for: blank) == DoseDraft(amount: nil, unit: .drop))
    }

    @Test func usesOnlyWhatWasEnteredFromTheLabel() {
        let entered = Medication(name: "Paracetamol", doseAmount: 2.5, doseUnit: .ml)
        #expect(DoseDraft.initial(for: entered) == DoseDraft(amount: 2.5, unit: .ml))
    }
}

struct CheckupScheduleTests {
    private let birth = calendar.date(from: DateComponents(year: 2026, month: 9, day: 14, hour: 6))!

    @Test func theAAPScheduleForTheFirstYear() {
        #expect(CheckupSchedule.visits.map(\.title) == [
            "First-week visit", "1-month visit", "2-month visit", "4-month visit",
            "6-month visit", "9-month visit", "12-month visit",
        ])
    }

    @Test func theNextOneFromTheBirthday() {
        // Two weeks old, nothing logged: the first-week visit is ten days
        // past, still inside its four-week window, so it's still the next one.
        let next = CheckupSchedule.next(birthDate: birth, visits: [], now: now, calendar: calendar)
        #expect(next?.visit.id == "first-week")

        // Once it's logged, the 1-month visit is next.
        let logged = DoctorVisit(date: calendar.date(byAdding: .day, value: 5, to: birth)!, kind: .checkup)
        let after = CheckupSchedule.next(birthDate: birth, visits: [logged], now: now, calendar: calendar)
        #expect(after?.visit.id == "1-month")
        #expect(after.map { CheckupSchedule.text($0, now: now, calendar: calendar) } == "1-month visit · around Oct 14 · in 2 weeks")
    }

    @Test func aSickVisitDoesntCountAsACheckup() {
        let sick = DoctorVisit(date: calendar.date(byAdding: .day, value: 5, to: birth)!, kind: .sick)
        #expect(CheckupSchedule.next(birthDate: birth, visits: [sick], now: now, calendar: calendar)?.visit.id == "first-week")
    }

    @Test func longPastAndNeverLoggedMovesOn() {
        let later = calendar.date(byAdding: .month, value: 3, to: birth)!
        #expect(CheckupSchedule.next(birthDate: birth, visits: [], now: later, calendar: calendar)?.visit.id == "4-month")
        #expect(CheckupSchedule.next(birthDate: nil, visits: [], now: now, calendar: calendar) == nil)
    }
}

struct ReportWindowTests {
    @Test func daysCountBackFromToday() {
        #expect(ReportWindow.days(7).start(now: now, calendar: calendar) == calendar.date(byAdding: .day, value: -6, to: calendar.startOfDay(for: now)))
        #expect(ReportWindow.days(7).dayCount(now: now, calendar: calendar) == 7)
    }

    @Test func theDefaultIsSinceTheVisitBeforeToday() {
        let lastWeek = DoctorVisit(date: daysAgo(6, hour: 10))
        let todays = DoctorVisit(date: daysAgo(0, hour: 9))
        let window = ReportWindow.defaultWindow(visits: [lastWeek, todays], now: now, calendar: calendar)
        #expect(window == .since(daysAgo(6, hour: 10)), "at today's appointment, count from the one before")
        #expect(window.start(now: now, calendar: calendar) == calendar.startOfDay(for: daysAgo(6)))
        #expect(window.title(now: now, calendar: calendar) == "Since Sep 22 (7 days)")
        #expect(ReportWindow.defaultWindow(visits: [], now: now, calendar: calendar) == .days(7))
    }

    @Test func theSummaryCarriesConcernsMedicinesAndFollowUp() {
        let concern = HealthConcern(uuid: UUID(), title: "Red left eye", kind: .eye, startedAt: daysAgo(2))
        let update = CareNote(date: daysAgo(1), kind: .eye, note: "less red today")
        update.concernID = concern.uuid
        let oldConcern = HealthConcern(title: "Hiccups", kind: .other, startedAt: daysAgo(40))
        oldConcern.resolvedAt = daysAgo(39)
        let doses = [hoursAgo(30), hoursAgo(6)].map { MedicationDose(medicationName: "Gas drops", time: $0) }
        let visit = DoctorVisit(date: daysAgo(6, hour: 10), kind: .checkup, provider: "Dr. Patel")
        visit.followUpNote = "Recheck the eye"

        let report = DaySummaryGenerator.report(
            entries: [], weights: [], careNotes: [update],
            concerns: [concern, oldConcern], doses: doses, visits: [visit],
            window: .since(visit.date), unit: .milliliters, weightUnit: .kilograms,
            profile: BabyProfile(name: "Nora", birthDate: nil), calendar: calendar, now: now)

        #expect(report.concerns.map(\.title) == ["Red left eye"], "only what was going on in the window")
        #expect(report.concerns.first?.statusText == "ongoing · day 3")
        #expect(report.concerns.first?.updates.count == 1)
        #expect(report.medicines.first?.count == 2)
        #expect(report.followUp?.note == "Recheck the eye")
        let text = DaySummaryGenerator.plainText(from: report)
        #expect(text.contains("Red left eye"))
        #expect(text.contains("Gas drops: 2 doses"))
        #expect(text.contains("Recheck the eye"))
    }

    @Test func aLongWindowGoesByTheWeek() {
        let feeds = (0..<28).map { FeedEntry(startTime: daysAgo($0, hour: 10), kind: .formula, amountML: 100) }
        let report = DaySummaryGenerator.report(
            entries: feeds, weights: [], window: .days(28), unit: .milliliters, weightUnit: .kilograms,
            profile: BabyProfile(name: "Nora", birthDate: nil), calendar: calendar, now: now)
        #expect(report.byWeek)
        #expect(report.days.count == 4)
        #expect(report.days.allSatisfy { $0.feedCount == 7 })
    }
}

struct HealthSyncTests {
    private let baby = UUID()

    @Test func everyHealthRecordRoundTripsThroughItsDTO() throws {
        let concern = HealthConcern(babyID: baby, title: "Red left eye", kind: .eye, startedAt: daysAgo(2), severity: .moderate,
                                    note: "goopy", loggedByName: "Sam")
        concern.resolvedAt = daysAgo(0)
        concern.outcome = "drops"
        let copy = HealthConcern(title: "", kind: .other)
        let concernDTO = try #require(HealthConcernDTO(entry: concern, userID: UUID()))
        let decoded = try SyncClient.decoder.decode(HealthConcernDTO.self, from: SyncClient.encoder.encode(concernDTO))
        decoded.apply(to: copy)
        #expect(copy.title == "Red left eye" && copy.kind == .eye && copy.severity == .moderate)
        #expect(copy.resolvedAt == concern.resolvedAt && copy.outcome == "drops" && !copy.needsUpload)

        let medication = Medication(babyID: baby, name: "Amoxicillin", doseAmount: 2.5, doseUnit: .ml, schedule: .everyNHours,
                                    intervalHours: 8, minHoursBetween: 6, maxDosesPer24h: 3, startDate: daysAgo(1),
                                    endDate: daysAgo(-9), instructions: "with food")
        let medicationCopy = Medication(name: "")
        try SyncClient.decoder.decode(MedicationDTO.self, from: SyncClient.encoder.encode(#require(MedicationDTO(entry: medication, userID: nil))))
            .apply(to: medicationCopy)
        #expect(medicationCopy.doseAmount == 2.5 && medicationCopy.schedule == .everyNHours && medicationCopy.intervalHours == 8)
        #expect(medicationCopy.maxDosesPer24h == 3 && medicationCopy.endDate == medication.endDate)

        let dose = MedicationDose(babyID: baby, medicationID: medication.uuid, medicationName: "Amoxicillin", time: hoursAgo(1),
                                  amount: 2.5, unit: .ml, loggedByName: "Annette")
        let doseCopy = MedicationDose(medicationName: "")
        try SyncClient.decoder.decode(MedicationDoseDTO.self, from: SyncClient.encoder.encode(#require(MedicationDoseDTO(entry: dose, userID: nil))))
            .apply(to: doseCopy)
        #expect(doseCopy.medicationID == medication.uuid && doseCopy.amount == 2.5 && doseCopy.unit == .ml)

        let visit = DoctorVisit(babyID: baby, date: daysAgo(3), kind: .followUp, provider: "Dr. Patel", reason: "weight")
        visit.followUpDate = daysAgo(-30)
        visit.weightEntryID = UUID()
        let visitCopy = DoctorVisit()
        try SyncClient.decoder.decode(DoctorVisitDTO.self, from: SyncClient.encoder.encode(#require(DoctorVisitDTO(entry: visit, userID: nil))))
            .apply(to: visitCopy)
        #expect(visitCopy.kind == .followUp && visitCopy.provider == "Dr. Patel" && visitCopy.weightEntryID == visit.weightEntryID)

        #expect(HealthConcernDTO(entry: HealthConcern(title: "x", kind: .other), userID: nil) == nil, "no baby, no row")
    }

    /// The late column: sent always (null included), read only when sent.
    @Test func aNoteKeepsItsConcernWhenTheFieldIsAbsent() throws {
        let concernID = UUID()
        let note = CareNote(babyID: baby, date: daysAgo(1), kind: .eye, note: "less red")
        note.concernID = concernID

        let unlinked = CareNote(babyID: baby, date: daysAgo(1), kind: .eye, note: "")
        let json = String(data: try SyncClient.encoder.encode(try #require(CareNoteDTO(entry: unlinked, userID: nil))), encoding: .utf8)!
        #expect(json.contains("\"concern_id\":null"), "an unlink is sent as null, so it reaches the other phone")

        // From a server or phone that doesn't know the field: it isn't there.
        let older = #"{"id":"\#(UUID().uuidString)","baby_id":"\#(baby.uuidString)","date":"2026-09-27T12:00:00.000Z","kind":"eye","note":"much better","logged_by_name":"","updated_at":"2026-09-28T12:00:00.000Z"}"#
        let fromOlder = try SyncClient.decoder.decode(CareNoteDTO.self, from: Data(older.utf8))
        #expect(!fromOlder.concernIDWasSent)
        fromOlder.apply(to: note)
        #expect(note.note == "much better")
        #expect(note.concernID == concernID, "an absent key keeps the link")

        // Sent as null: that's an unlink, and it's honoured.
        let explicit = older.replacingOccurrences(of: #""note":"much better""#, with: #""note":"x","concern_id":null"#)
        try SyncClient.decoder.decode(CareNoteDTO.self, from: Data(explicit.utf8)).apply(to: note)
        #expect(note.concernID == nil)
    }

    @Test func theTimelineFindsHealthRecords() {
        let concern = HealthConcern(babyID: baby, title: "Red left eye", kind: .eye, startedAt: daysAgo(3))
        let dose = MedicationDose(babyID: baby, medicationName: "Vitamin D", time: hoursAgo(4))
        let visit = DoctorVisit(babyID: baby, date: daysAgo(1), kind: .checkup, provider: "Dr. Patel")
        let sources = TimelineSources(concerns: [concern], doses: [dose], visits: [visit])

        #expect(TimelineBuilder.items(sources, babyID: baby, filter: .only(.health)).count == 3)
        #expect(TimelineBuilder.items(sources, babyID: baby, query: "eye").map(\.category) == [.health])
        #expect(TimelineBuilder.items(sources, babyID: baby, query: "patel").count == 1)
        #expect(TimelineBuilder.categoriesPresent(sources, babyID: baby) == [.health])
    }
}
