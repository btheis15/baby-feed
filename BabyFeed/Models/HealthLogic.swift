import Foundation

// MARK: Concerns

enum ConcernStats {
    /// Which day of it this is, the first day being day 1: "day 3".
    static func dayNumber(_ concern: HealthConcern, now: Date, calendar: Calendar) -> Int {
        RelativeAge.days(from: concern.startedAt, to: concern.resolvedAt ?? now, calendar: calendar) + 1
    }

    /// "ongoing · day 3", or "lasted 4 days".
    static func statusText(_ concern: HealthConcern, now: Date, calendar: Calendar) -> String {
        RelativeAge.span(start: concern.startedAt, end: concern.resolvedAt, now: now, calendar: calendar)
    }

    /// "since Sep 16 · 12 days ago", the way a doctor asks.
    static func startedText(_ concern: HealthConcern, now: Date, calendar: Calendar) -> String {
        var style = Date.FormatStyle.dateTime.month(.abbreviated).day()
        style.timeZone = calendar.timeZone
        let ago = RelativeAge.ago(concern.startedAt, now: now, calendar: calendar)
        return "since \(concern.startedAt.formatted(style)) · \(ago.lowercased() == "today" ? "today" : ago)"
    }

    /// A week with nothing added asks "Still going on?".
    static let checkInAfterDays = 7

    /// Ongoing, and no update, note or check-in for a week. It's a question,
    /// never an answer: a concern is only ever marked better by a parent.
    static func needsCheckIn(_ concern: HealthConcern, notes: [CareNote], now: Date, calendar: Calendar) -> Bool {
        guard concern.isOngoing, concern.deletedAt == nil else { return false }
        let updates = notes.active(for: nil).filter { $0.concernID != nil && $0.concernID == concern.uuid }.map(\.date)
        let last = ([concern.startedAt, concern.updatedAt] + updates).max() ?? concern.startedAt
        return RelativeAge.days(from: last, to: now, calendar: calendar) >= checkInAfterDays
    }

    /// The notes that are updates on this concern, newest first.
    static func updates(for concern: HealthConcern, in notes: [CareNote]) -> [CareNote] {
        guard let id = concern.uuid else { return [] }
        return notes.active(for: nil).filter { $0.concernID == id }.sorted { $0.date > $1.date }
    }
}

// MARK: Medicines

enum MedicationStats {
    /// This medicine's doses, newest first: by id, or by name for a dose
    /// logged before the medicine was set up.
    static func doses(of medication: Medication, in doses: [MedicationDose]) -> [MedicationDose] {
        let name = medication.name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return doses.active(for: nil).filter { dose in
            if let id = dose.medicationID { return id == medication.uuid }
            return !name.isEmpty && dose.medicationName.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == name
        }
        .sorted { $0.time > $1.time }
    }

    static func lastDose(of medication: Medication, in doses: [MedicationDose]) -> MedicationDose? {
        Self.doses(of: medication, in: doses).first
    }

    static func count(of medication: Medication, in doses: [MedicationDose], within interval: TimeInterval, now: Date) -> Int {
        Self.doses(of: medication, in: doses).filter { $0.time > now.addingTimeInterval(-interval) && $0.time <= now }.count
    }

    static func countToday(of medication: Medication, in doses: [MedicationDose], now: Date, calendar: Calendar) -> Int {
        Self.doses(of: medication, in: doses).filter { calendar.isDate($0.time, inSameDayAs: now) && $0.time <= now }.count
    }

    /// When the next one is due, or nil for "as needed" and for a course
    /// that's over. A daily medicine is due at the time of day it was last
    /// given (9 AM if it never has been), once it hasn't been given today.
    static func nextDue(_ medication: Medication, doses: [MedicationDose], now: Date, calendar: Calendar) -> Date? {
        guard medication.deletedAt == nil, medication.isCurrent(at: now) else { return nil }
        let last = lastDose(of: medication, in: doses)
        switch medication.schedule {
        case .asNeeded:
            return nil
        case .everyNHours:
            guard let hours = medication.intervalHours, hours > 0 else { return nil }
            guard let last else { return medication.startDate }
            return last.time.addingTimeInterval(hours * 3600)
        case .daily:
            let perDay = max(1, medication.timesPerDay ?? 1)
            let today = countToday(of: medication, in: doses, now: now, calendar: calendar)
            let startOfDay = calendar.startOfDay(for: now)
            if today >= perDay {
                return calendar.date(byAdding: .day, value: 1, to: startOfDay).map { dueTime(on: $0, last: last, calendar: calendar) }
            }
            if perDay > 1, let last, calendar.isDate(last.time, inSameDayAs: now) {
                return last.time.addingTimeInterval(24 * 3600 / Double(perDay))
            }
            return dueTime(on: startOfDay, last: last, calendar: calendar)
        }
    }

    private static func dueTime(on day: Date, last: MedicationDose?, calendar: Calendar) -> Date {
        let parts = last.map { calendar.dateComponents([.hour, .minute], from: $0.time) }
        return calendar.date(bySettingHour: parts?.hour ?? 9, minute: parts?.minute ?? 0, second: 0, of: day) ?? day
    }

    static func isDue(_ medication: Medication, doses: [MedicationDose], now: Date, calendar: Calendar) -> Bool {
        guard let due = nextDue(medication, doses: doses, now: now, calendar: calendar) else { return false }
        return due <= now
    }
}

/// What to say before a dose is logged. Notices, never blocks: the parent
/// may well know better (the doctor said otherwise, the label has changed),
/// so Save stays and reads "Log anyway". Nothing here suggests a dose.
enum MedicationSafety {
    enum Notice: Equatable, Identifiable {
        case tooSoon(last: Date, minHours: Double)
        case dailyMaxReached(count: Int, max: Int)
        case alreadyGivenToday(at: Date, by: String)
        case courseEnded(on: Date)
        case recentByOtherCaregiver(at: Date, by: String)

        var id: String {
            switch self {
            case .tooSoon: "tooSoon"
            case .dailyMaxReached: "dailyMax"
            case .alreadyGivenToday: "givenToday"
            case .courseEnded: "courseEnded"
            case .recentByOtherCaregiver: "otherCaregiver"
            }
        }
    }

    /// How recent another caregiver's dose has to be to mention, when the
    /// medicine gives no minimum gap of its own.
    static let otherCaregiverWindow: TimeInterval = 4 * 3600

    static func notices(
        for medication: Medication,
        doses: [MedicationDose],
        loggingAs caregiver: String,
        now: Date,
        calendar: Calendar
    ) -> [Notice] {
        var notices: [Notice] = []
        let mine = MedicationStats.doses(of: medication, in: doses).filter { $0.time <= now }
        let last = mine.first

        if let endDate = medication.endDate, endDate < calendar.startOfDay(for: now) {
            notices.append(.courseEnded(on: endDate))
        }
        if let last, let minHours = medication.minHoursBetween, minHours > 0,
           now.timeIntervalSince(last.time) < minHours * 3600 {
            notices.append(.tooSoon(last: last.time, minHours: minHours))
        }
        if let max = medication.maxDosesPer24h {
            let count = mine.filter { $0.time > now.addingTimeInterval(-24 * 3600) }.count
            if count >= max { notices.append(.dailyMaxReached(count: count, max: max)) }
        }
        if medication.schedule == .daily, let last {
            let perDay = Swift.max(1, medication.timesPerDay ?? 1)
            let today = mine.filter { calendar.isDate($0.time, inSameDayAs: now) }.count
            if today >= perDay { notices.append(.alreadyGivenToday(at: last.time, by: last.loggedByName)) }
        }
        if let last {
            let window = medication.minHoursBetween.map { $0 * 3600 } ?? otherCaregiverWindow
            let name = last.loggedByName.trimmingCharacters(in: .whitespacesAndNewlines)
            let me = caregiver.trimmingCharacters(in: .whitespacesAndNewlines)
            if !name.isEmpty, name.caseInsensitiveCompare(me) != .orderedSame,
               now.timeIntervalSince(last.time) < window {
                notices.append(.recentByOtherCaregiver(at: last.time, by: name))
            }
        }
        return notices
    }

    /// Doses of the same medicine closer together than it allows (an hour
    /// when it doesn't say): the usual sign of two phones logging the same
    /// dose while apart. The later one of each pair.
    static func possibleDuplicates(medications: [Medication], doses: [MedicationDose]) -> [MedicationDose] {
        var flagged: [MedicationDose] = []
        for medication in medications.active(for: nil) {
            let gap = (medication.minHoursBetween.map { $0 * 3600 }) ?? 3600
            let ordered = MedicationStats.doses(of: medication, in: doses).reversed()
            var previous: MedicationDose?
            for dose in ordered {
                if let previous, dose.time.timeIntervalSince(previous.time) < gap {
                    flagged.append(dose)
                }
                previous = dose
            }
        }
        return flagged
    }

    /// What the app says it is and isn't, everywhere a dose is logged.
    static let disclaimer = "Baby Feed records what was given. It never suggests a dose: that comes from your pediatrician, pharmacist or the label."
}

/// What the dose sheet starts with. The medicine's own amount if one was
/// entered from the label or the doctor, or nothing: it never invents one.
struct DoseDraft: Equatable {
    var amount: Double?
    var unit: DoseUnit

    static func initial(for medication: Medication?) -> DoseDraft {
        DoseDraft(amount: medication?.doseAmount, unit: medication?.doseUnit ?? .ml)
    }
}

// MARK: Checkups

/// The AAP's well-child schedule for the first year: the first week, then
/// 1, 2, 4, 6, 9 and 12 months.
enum CheckupSchedule {
    struct Visit: Equatable, Identifiable {
        let id: String
        let title: String
        /// Days after birth, for the first-week visit.
        let days: Int?
        /// Months after birth, for the rest.
        let months: Int?
    }

    static let visits: [Visit] = [
        Visit(id: "first-week", title: "First-week visit", days: 4, months: nil),
        Visit(id: "1-month", title: "1-month visit", days: nil, months: 1),
        Visit(id: "2-month", title: "2-month visit", days: nil, months: 2),
        Visit(id: "4-month", title: "4-month visit", days: nil, months: 4),
        Visit(id: "6-month", title: "6-month visit", days: nil, months: 6),
        Visit(id: "9-month", title: "9-month visit", days: nil, months: 9),
        Visit(id: "12-month", title: "12-month visit", days: nil, months: 12),
    ]

    static let sourceID = "aap-well-child"

    /// A logged checkup this close to a visit's date counts as that visit.
    static let windowBefore: TimeInterval = 14 * 86_400
    static let windowAfter: TimeInterval = 28 * 86_400

    static func date(of visit: Visit, birthDate: Date, calendar: Calendar) -> Date {
        let birthDay = calendar.startOfDay(for: birthDate)
        if let days = visit.days { return calendar.date(byAdding: .day, value: days, to: birthDay) ?? birthDay }
        return calendar.date(byAdding: .month, value: visit.months ?? 0, to: birthDay) ?? birthDay
    }

    /// The next checkup not yet done and not long past, with its date.
    static func next(birthDate: Date?, visits logged: [DoctorVisit], now: Date, calendar: Calendar)
        -> (visit: Visit, date: Date)? {
        guard let birthDate else { return nil }
        let checkups = logged.active(for: nil).filter { $0.kind == .checkup }.map(\.date)
        for visit in visits {
            let date = date(of: visit, birthDate: birthDate, calendar: calendar)
            let done = checkups.contains { $0 >= date.addingTimeInterval(-windowBefore) && $0 <= date.addingTimeInterval(windowAfter) }
            if done { continue }
            // Long past and never logged: not worth nagging about now.
            if date.addingTimeInterval(windowAfter) < now { continue }
            return (visit, date)
        }
        return nil
    }

    /// "2-month visit · around Nov 16 · in 7 weeks"
    static func text(_ next: (visit: Visit, date: Date), now: Date, calendar: Calendar) -> String {
        var style = Date.FormatStyle.dateTime.month(.abbreviated).day()
        style.timeZone = calendar.timeZone
        let days = RelativeAge.days(from: now, to: next.date, calendar: calendar)
        let when: String
        switch days {
        case ..<0: when = "was due \(RelativeAge.ago(next.date, now: now, calendar: calendar).lowercased())"
        case 0: when = "today"
        case 1: when = "tomorrow"
        case 2...13: when = "in \(days) days"
        default: when = "in \(days / 7) weeks"
        }
        return "\(next.visit.title) · around \(next.date.formatted(style)) · \(when)"
    }
}

// MARK: The pediatrician summary's window

/// How far back the pediatrician summary looks: a number of days, or since a
/// date (the last visit, by default).
enum ReportWindow: Hashable {
    case days(Int)
    case since(Date)

    func start(now: Date, calendar: Calendar) -> Date {
        switch self {
        case .days(let days):
            return calendar.date(byAdding: .day, value: -(max(1, days) - 1), to: calendar.startOfDay(for: now)) ?? now
        case .since(let date):
            return calendar.startOfDay(for: date)
        }
    }

    /// Whole calendar days covered, today included.
    func dayCount(now: Date, calendar: Calendar) -> Int {
        RelativeAge.days(from: start(now: now, calendar: calendar), to: now, calendar: calendar) + 1
    }

    func title(now: Date, calendar: Calendar) -> String {
        switch self {
        case .days(let days): return "Last \(days) days"
        case .since(let date):
            var style = Date.FormatStyle.dateTime.month(.abbreviated).day()
            style.timeZone = calendar.timeZone
            return "Since \(date.formatted(style)) (\(dayCount(now: now, calendar: calendar)) days)"
        }
    }

    /// The default: since the last visit before today (at the appointment,
    /// the one being had today isn't the one to count from), or the last
    /// week without one.
    static func defaultWindow(visits: [DoctorVisit], now: Date, calendar: Calendar) -> ReportWindow {
        let today = calendar.startOfDay(for: now)
        let past = visits.active(for: nil).filter { $0.date < today }.map(\.date)
        guard let last = past.max() else { return .days(7) }
        return .since(last)
    }
}
