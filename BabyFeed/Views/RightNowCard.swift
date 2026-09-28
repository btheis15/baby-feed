import SwiftData
import SwiftUI

/// "Right now" on Today: at most three things that want doing, and nothing at
/// all when nothing does. A medicine that's due (with Give), a concern that's
/// gone a week without an update, and a checkup this week.
struct RightNowCard: View {
    let babyID: UUID?
    let birthDate: Date?

    @Environment(\.calendar) private var calendar
    @Environment(\.timeZone) private var timeZone
    @Environment(AppRouter.self) private var router
    @Query(sort: \Medication.name) private var medications: [Medication]
    @Query(sort: \MedicationDose.time, order: .reverse) private var doses: [MedicationDose]
    @Query(sort: \HealthConcern.startedAt, order: .reverse) private var concerns: [HealthConcern]
    @Query(sort: \CareNote.date, order: .reverse) private var notes: [CareNote]
    @Query(sort: \DoctorVisit.date, order: .reverse) private var visits: [DoctorVisit]

    private enum Row: Identifiable {
        case medicine(Medication, due: Date)
        case checkIn(HealthConcern)
        case checkup(String)

        var id: String {
            switch self {
            case .medicine(let medication, _): "medicine-\(medication.uuid?.uuidString ?? "")"
            case .checkIn(let concern): "concern-\(concern.uuid?.uuidString ?? "")"
            case .checkup: "checkup"
            }
        }
    }

    private var rows: [Row] {
        let now = Date.now
        let babyDoses = doses.active(for: babyID)
        var rows: [Row] = []
        for medication in medications.active(for: babyID) {
            if let due = MedicationStats.nextDue(medication, doses: babyDoses, now: now, calendar: calendar), due <= now {
                rows.append(.medicine(medication, due: due))
            }
        }
        let babyNotes = notes.active(for: babyID)
        for concern in concerns.active(for: babyID)
        where ConcernStats.needsCheckIn(concern, notes: babyNotes, now: now, calendar: calendar) {
            rows.append(.checkIn(concern))
        }
        if let next = CheckupSchedule.next(birthDate: birthDate, visits: visits.active(for: babyID), now: now, calendar: calendar),
           abs(RelativeAge.days(from: now, to: next.date, calendar: calendar)) <= 7 {
            rows.append(.checkup(CheckupSchedule.text(next, now: now, calendar: calendar)))
        }
        return Array(rows.prefix(3))
    }

    var body: some View {
        let rows = rows
        if !rows.isEmpty {
            Section("Right now") {
                ForEach(rows) { row in
                    switch row {
                    case .medicine(let medication, let due):
                        HStack {
                            Label {
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(medication.name).font(.headline)
                                    Text("Due since \(ClockText.since(due, now: .now, in: timeZone))")
                                        .font(.subheadline)
                                        .foregroundStyle(.secondary)
                                }
                            } icon: {
                                Image(systemName: medication.kind.systemImage).foregroundStyle(.mint)
                            }
                            Spacer()
                            Button("Give") { router.sheet = .giveDose(medication.persistentModelID) }
                                .buttonStyle(.borderedProminent)
                                .tint(.mint)
                        }
                    case .checkIn(let concern):
                        Button {
                            router.tab = .health
                        } label: {
                            Label {
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(concern.title.isEmpty ? concern.kind.title : concern.title).font(.headline)
                                    Text("Still going on? Day \(ConcernStats.dayNumber(concern, now: .now, calendar: calendar))")
                                        .font(.subheadline)
                                        .foregroundStyle(.secondary)
                                }
                            } icon: {
                                Image(systemName: concern.kind.systemImage).foregroundStyle(.orange)
                            }
                        }
                        .buttonStyle(.plain)
                    case .checkup(let text):
                        Button {
                            router.tab = .health
                        } label: {
                            Label(EntryRow.wrappingAtDots(text), systemImage: "calendar")
                                .font(.subheadline)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }
}
