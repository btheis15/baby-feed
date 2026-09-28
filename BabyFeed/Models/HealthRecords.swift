import Foundation
import SwiftData

/// Something going on, with a start and, once it's over, an end: "Red left
/// eye", started Sep 16. A `CareNote` is a moment; a concern is an episode,
/// and notes about it ("less red today") link to it by `concernID`.
///
/// It's never marked better by itself. After a week with no update it asks
/// "Still going on?", and the parent says.
@Model
final class HealthConcern {
    var uuid: UUID?
    var babyID: UUID?
    var title: String = ""
    /// A `CareNoteKind`, so it groups with the notes about it.
    var kindRaw: String = CareNoteKind.other.rawValue
    var startedAt: Date = Date()
    /// Nil while it's going on.
    var resolvedAt: Date?
    /// 1–3, at its worst.
    var severityRaw: Int?
    var note: String = ""
    /// How it ended: "cleared with drops".
    var outcome: String = ""
    var loggedByName: String = ""
    var updatedAt: Date = Date()
    var deletedAt: Date?
    var needsUpload: Bool = true

    init(
        uuid: UUID = UUID(),
        babyID: UUID? = nil,
        title: String,
        kind: CareNoteKind,
        startedAt: Date = .now,
        severity: CareNoteSeverity? = nil,
        note: String = "",
        loggedByName: String = ""
    ) {
        self.uuid = uuid
        self.babyID = babyID
        self.title = title
        self.kindRaw = kind.rawValue
        self.startedAt = startedAt
        self.severityRaw = severity?.rawValue
        self.note = note
        self.loggedByName = loggedByName
        self.updatedAt = .now
        self.needsUpload = true
    }

    var kind: CareNoteKind {
        get { CareNoteKind(rawValue: kindRaw) ?? .other }
        set { kindRaw = newValue.rawValue }
    }

    var severity: CareNoteSeverity? {
        get { severityRaw.flatMap(CareNoteSeverity.init(rawValue:)) }
        set { severityRaw = newValue?.rawValue }
    }

    var isOngoing: Bool { resolvedAt == nil }

    func markChanged() {
        updatedAt = .now
        needsUpload = true
    }

    func softDelete() {
        deletedAt = .now
        markChanged()
    }
}

/// A medicine or supplement, as the label or the doctor gives it. Every
/// number here is typed by a parent. The app records what's given; it never
/// suggests a dose.
@Model
final class Medication {
    var uuid: UUID?
    var babyID: UUID?
    var name: String = ""
    var kindRaw: String = MedicationKind.medicine.rawValue
    /// From the label or the doctor; nil until someone types it.
    var doseAmount: Double?
    var doseUnitRaw: String = DoseUnit.ml.rawValue
    var scheduleRaw: String = MedicationSchedule.asNeeded.rawValue
    var timesPerDay: Int?
    var intervalHours: Double?
    /// The shortest gap the label or doctor allows, for "too soon" notices.
    var minHoursBetween: Double?
    var maxDosesPer24h: Int?
    var startDate: Date = Date()
    /// When a course ends; nil for an ongoing one.
    var endDate: Date?
    var instructions: String = ""
    var loggedByName: String = ""
    var updatedAt: Date = Date()
    var deletedAt: Date?
    var needsUpload: Bool = true

    init(
        uuid: UUID = UUID(),
        babyID: UUID? = nil,
        name: String,
        kind: MedicationKind = .medicine,
        doseAmount: Double? = nil,
        doseUnit: DoseUnit = .ml,
        schedule: MedicationSchedule = .asNeeded,
        timesPerDay: Int? = nil,
        intervalHours: Double? = nil,
        minHoursBetween: Double? = nil,
        maxDosesPer24h: Int? = nil,
        startDate: Date = .now,
        endDate: Date? = nil,
        instructions: String = "",
        loggedByName: String = ""
    ) {
        self.uuid = uuid
        self.babyID = babyID
        self.name = name
        self.kindRaw = kind.rawValue
        self.doseAmount = doseAmount
        self.doseUnitRaw = doseUnit.rawValue
        self.scheduleRaw = schedule.rawValue
        self.timesPerDay = timesPerDay
        self.intervalHours = intervalHours
        self.minHoursBetween = minHoursBetween
        self.maxDosesPer24h = maxDosesPer24h
        self.startDate = startDate
        self.endDate = endDate
        self.instructions = instructions
        self.loggedByName = loggedByName
        self.updatedAt = .now
        self.needsUpload = true
    }

    var kind: MedicationKind {
        get { MedicationKind(rawValue: kindRaw) ?? .other }
        set { kindRaw = newValue.rawValue }
    }

    var doseUnit: DoseUnit {
        get { DoseUnit(rawValue: doseUnitRaw) ?? .other }
        set { doseUnitRaw = newValue.rawValue }
    }

    var schedule: MedicationSchedule {
        get { MedicationSchedule(rawValue: scheduleRaw) ?? .asNeeded }
        set { scheduleRaw = newValue.rawValue }
    }

    /// Whether it's still being given: started, and not past its course.
    func isCurrent(at date: Date) -> Bool {
        guard startDate <= date.addingTimeInterval(24 * 3600) else { return false }
        guard let endDate else { return true }
        return endDate >= date
    }

    func markChanged() {
        updatedAt = .now
        needsUpload = true
    }

    func softDelete() {
        deletedAt = .now
        markChanged()
    }
}

/// One dose given. The medicine's name is copied onto it, so it still reads
/// right after the medicine is renamed or deleted.
@Model
final class MedicationDose {
    var uuid: UUID?
    var babyID: UUID?
    var medicationID: UUID?
    var medicationName: String = ""
    var time: Date = Date()
    var amount: Double?
    var unitRaw: String?
    var note: String = ""
    var loggedByName: String = ""
    var updatedAt: Date = Date()
    var deletedAt: Date?
    var needsUpload: Bool = true

    init(
        uuid: UUID = UUID(),
        babyID: UUID? = nil,
        medicationID: UUID? = nil,
        medicationName: String,
        time: Date = .now,
        amount: Double? = nil,
        unit: DoseUnit? = nil,
        note: String = "",
        loggedByName: String = ""
    ) {
        self.uuid = uuid
        self.babyID = babyID
        self.medicationID = medicationID
        self.medicationName = medicationName
        self.time = time
        self.amount = amount
        self.unitRaw = unit?.rawValue
        self.note = note
        self.loggedByName = loggedByName
        self.updatedAt = .now
        self.needsUpload = true
    }

    var unit: DoseUnit? {
        get { unitRaw.flatMap(DoseUnit.init(rawValue:)) }
        set { unitRaw = newValue?.rawValue }
    }

    /// "2.5 ml", or nil when no amount was recorded.
    var amountText: String? {
        guard let amount else { return nil }
        return DoseUnit.format(amount, unit: unit ?? .other)
    }

    func markChanged() {
        updatedAt = .now
        needsUpload = true
    }

    func softDelete() {
        deletedAt = .now
        markChanged()
    }
}

/// A visit to the doctor, and what they said.
@Model
final class DoctorVisit {
    var uuid: UUID?
    var babyID: UUID?
    var date: Date = Date()
    var kindRaw: String = VisitKind.checkup.rawValue
    var provider: String = ""
    var reason: String = ""
    /// "What the doctor said."
    var doctorNotes: String = ""
    var followUpDate: Date?
    var followUpNote: String = ""
    /// Free text for now: "2-month shots".
    var vaccines: String = ""
    /// The weigh-in taken at the visit, so the growth numbers pick it up.
    var weightEntryID: UUID?
    var loggedByName: String = ""
    var updatedAt: Date = Date()
    var deletedAt: Date?
    var needsUpload: Bool = true

    init(
        uuid: UUID = UUID(),
        babyID: UUID? = nil,
        date: Date = .now,
        kind: VisitKind = .checkup,
        provider: String = "",
        reason: String = "",
        doctorNotes: String = "",
        loggedByName: String = ""
    ) {
        self.uuid = uuid
        self.babyID = babyID
        self.date = date
        self.kindRaw = kind.rawValue
        self.provider = provider
        self.reason = reason
        self.doctorNotes = doctorNotes
        self.loggedByName = loggedByName
        self.updatedAt = .now
        self.needsUpload = true
    }

    var kind: VisitKind {
        get { VisitKind(rawValue: kindRaw) ?? .other }
        set { kindRaw = newValue.rawValue }
    }

    func markChanged() {
        updatedAt = .now
        needsUpload = true
    }

    func softDelete() {
        deletedAt = .now
        markChanged()
    }
}

enum MedicationKind: String, CaseIterable, Identifiable, Codable {
    case medicine, supplement, topical, other

    var id: String { rawValue }

    var title: String {
        switch self {
        case .medicine: "Medicine"
        case .supplement: "Supplement"
        case .topical: "Cream or ointment"
        case .other: "Other"
        }
    }

    var systemImage: String {
        switch self {
        case .medicine: "pills.fill"
        case .supplement: "drop.fill"
        case .topical: "hand.raised.fill"
        case .other: "cross.case.fill"
        }
    }
}

/// Millilitres, not teaspoons: the AAP's advice is to measure liquid medicine
/// in ml with the dosing tool that comes with it.
enum DoseUnit: String, CaseIterable, Identifiable, Codable {
    case ml, drop, mg, iu, tablet, application, other

    var id: String { rawValue }

    var title: String {
        switch self {
        case .ml: "ml"
        case .drop: "drops"
        case .mg: "mg"
        case .iu: "IU"
        case .tablet: "tablets"
        case .application: "applications"
        case .other: "doses"
        }
    }

    /// "2.5 ml", "1 drop", "400 IU".
    static func format(_ amount: Double, unit: DoseUnit) -> String {
        let number = amount.formatted(.number.precision(.fractionLength(0...2)))
        switch unit {
        case .drop: return amount == 1 ? "1 drop" : "\(number) drops"
        case .tablet: return amount == 1 ? "1 tablet" : "\(number) tablets"
        case .application: return amount == 1 ? "1 application" : "\(number) applications"
        case .other: return amount == 1 ? "1 dose" : "\(number) doses"
        case .ml, .mg, .iu: return "\(number) \(unit.title)"
        }
    }
}

enum MedicationSchedule: String, CaseIterable, Identifiable, Codable {
    case asNeeded, daily, everyNHours

    var id: String { rawValue }

    var title: String {
        switch self {
        case .asNeeded: "As needed"
        case .daily: "Every day"
        case .everyNHours: "Every few hours"
        }
    }
}

enum VisitKind: String, CaseIterable, Identifiable, Codable {
    case checkup, sick, followUp, specialist, urgentCare, emergency, telehealth, other

    var id: String { rawValue }

    var title: String {
        switch self {
        case .checkup: "Checkup"
        case .sick: "Sick visit"
        case .followUp: "Follow-up"
        case .specialist: "Specialist"
        case .urgentCare: "Urgent care"
        case .emergency: "Emergency"
        case .telehealth: "Telehealth"
        case .other: "Other"
        }
    }
}
