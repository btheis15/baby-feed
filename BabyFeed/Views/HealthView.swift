import SwiftData
import SwiftUI

/// Everything a doctor asks about in the first year, in one tab: what's going
/// on and since when, which medicines were given and by whom, the last visit
/// and the next checkup, and the notes kept for the appointment.
struct HealthView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.calendar) private var calendar
    @Environment(\.timeZone) private var timeZone
    @Environment(AppRouter.self) private var router

    @Query(sort: \HealthConcern.startedAt, order: .reverse) private var concerns: [HealthConcern]
    @Query(sort: \Medication.name) private var medications: [Medication]
    @Query(sort: \MedicationDose.time, order: .reverse) private var doses: [MedicationDose]
    @Query(sort: \DoctorVisit.date, order: .reverse) private var visits: [DoctorVisit]
    @Query(sort: \CareNote.date, order: .reverse) private var notes: [CareNote]

    @AppStorage(AppSettings.currentBabyIDKey) private var currentBabyIDRaw = ""
    @AppStorage(BabyProfile.nameKey) private var babyName = ""
    @AppStorage(BabyProfile.birthDateKey) private var birthInterval: Double = 0
    @AppStorage(AppSettings.feedingStyleKey) private var feedingStyleRaw = FeedingStyle.formula.rawValue
    @AppStorage("health.vitaminDOfferDismissed") private var vitaminDOfferDismissed = false

    @State private var sync = SyncEngine.shared
    @State private var showSummary = false

    private var babyID: UUID? { UUID(uuidString: currentBabyIDRaw) }
    private var displayName: String { babyName.isEmpty ? "your baby" : babyName }

    var body: some View {
        let now = Date.now
        let babyConcerns = concerns.active(for: babyID)
        let ongoing = babyConcerns.filter(\.isOngoing)
        let past = babyConcerns.filter { !$0.isOngoing }
        let babyMedications = medications.active(for: babyID)
        let current = babyMedications.filter { $0.isCurrent(at: now) }
        let babyDoses = doses.active(for: babyID)
        let babyVisits = visits.active(for: babyID)
        let babyNotes = notes.active(for: babyID)

        NavigationStack {
            List {
                Section {
                    Button {
                        showSummary = true
                    } label: {
                        Label {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Summary for the pediatrician")
                                    .foregroundStyle(Color.primary)
                                Text(ReportWindow.defaultWindow(visits: babyVisits, now: now, calendar: calendar)
                                    .title(now: now, calendar: calendar))
                                    .font(.footnote)
                                    .foregroundStyle(Color.secondary)
                            }
                        } icon: {
                            // The same icon as the Timeline's button for it.
                            Image(systemName: "stethoscope")
                        }
                    }
                }

                if sync.serverNeedsUpdateForHealth {
                    Section {
                        Label("Your Mac mini needs an update to share health records with the other phone. They're safe on this iPhone until then.",
                              systemImage: "arrow.triangle.2.circlepath")
                            .font(.footnote)
                            .foregroundStyle(.orange)
                    }
                }

                duplicatesSection(medications: babyMedications, doses: babyDoses, now: now)
                checkupSection(visits: babyVisits, now: now)
                vitaminDSection(medications: babyMedications)

                if !ongoing.isEmpty {
                    Section("Ongoing") {
                        ForEach(ongoing) { concern in
                            concernRow(concern, notes: babyNotes, now: now)
                        }
                    }
                }

                Section {
                    ForEach(current) { medication in
                        medicationRow(medication, doses: babyDoses, now: now)
                    }
                    Button {
                        router.sheet = .newMedication(vitaminD: false)
                    } label: {
                        Label("Add a medicine or supplement", systemImage: "plus")
                    }
                } header: {
                    Text("Medicines")
                } footer: {
                    Text(MedicationSafety.disclaimer)
                }

                Section("Doctor visits") {
                    ForEach(babyVisits.prefix(5)) { visit in
                        Button {
                            router.sheet = .editEntry(.visit(visit.persistentModelID))
                        } label: {
                            TimelineRow(item: .visit(visit), unit: .ounces, weightUnit: .poundsOunces, showsDay: true)
                        }
                        .buttonStyle(.plain)
                    }
                    Button {
                        router.sheet = .newEntry(.visit)
                    } label: {
                        Label("Log a visit", systemImage: "plus")
                    }
                }

                Section {
                    NavigationLink {
                        CareNotesView(babyName: displayName)
                    } label: {
                        Label {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Notes for the doctor")
                                Text(notesSubtitle(notes: babyNotes, visits: babyVisits, now: now))
                                    .font(.footnote)
                                    .foregroundStyle(.secondary)
                            }
                        } icon: {
                            Image(systemName: "note.text")
                        }
                    }
                }

                if !past.isEmpty {
                    Section("Past concerns") {
                        ForEach(past.prefix(10)) { concern in
                            concernRow(concern, notes: babyNotes, now: now)
                        }
                    }
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle("Health")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Menu {
                        Button { router.sheet = .newEntry(.medicine) } label: { Label("Give a medicine", systemImage: "pills.fill") }
                        Button { router.sheet = .newEntry(.concern) } label: { Label("New concern", systemImage: "cross.case.fill") }
                        Button { router.sheet = .newEntry(.visit) } label: { Label("Doctor visit", systemImage: "stethoscope") }
                        Button { router.sheet = .newEntry(.note) } label: { Label("Note for the doctor", systemImage: "note.text") }
                        Button { router.sheet = .newMedication(vitaminD: false) } label: { Label("Add a medicine", systemImage: "plus") }
                    } label: {
                        Label("Add", systemImage: "plus")
                    }
                }
            }
            .sheet(isPresented: $showSummary) {
                SummarySheet()
            }
        }
    }

    // MARK: Rows

    private func concernRow(_ concern: HealthConcern, notes: [CareNote], now: Date) -> some View {
        NavigationLink {
            ConcernDetailView(concern: concern)
        } label: {
            VStack(alignment: .leading, spacing: 3) {
                HStack {
                    Label(concern.title.isEmpty ? concern.kind.title : concern.title, systemImage: concern.kind.systemImage)
                        .font(.headline)
                    Spacer(minLength: 8)
                    if ConcernStats.needsCheckIn(concern, notes: notes, now: now, calendar: calendar) {
                        Text("Still going on?")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.orange)
                    }
                }
                Text(EntryRow.wrappingAtDots(concern.isOngoing
                     ? "day \(ConcernStats.dayNumber(concern, now: now, calendar: calendar)) · \(ConcernStats.startedText(concern, now: now, calendar: calendar))"
                     : "\(ConcernStats.statusText(concern, now: now, calendar: calendar)) · \(ConcernStats.startedText(concern, now: now, calendar: calendar))"))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                if let latest = ConcernStats.updates(for: concern, in: notes).first, !latest.note.isEmpty {
                    Text("\"\(latest.note)\" · \(ClockText.since(latest.date, now: now, in: timeZone))")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            .padding(.vertical, 2)
        }
    }

    private func medicationRow(_ medication: Medication, doses: [MedicationDose], now: Date) -> some View {
        let last = MedicationStats.lastDose(of: medication, in: doses)
        let due = MedicationStats.isDue(medication, doses: doses, now: now, calendar: calendar)
        let givenToday = MedicationStats.countToday(of: medication, in: doses, now: now, calendar: calendar) > 0
        return HStack(spacing: 12) {
            NavigationLink {
                MedicationDetailView(medication: medication)
            } label: {
                VStack(alignment: .leading, spacing: 2) {
                    Text(medication.name).font(.headline)
                    Text(EntryRow.joined([
                        MedicationDetailView.scheduleText(medication).lowercased(),
                        last.map { dose in
                            (medication.schedule == .daily && givenToday ? "✓ " : "last ")
                                + ClockText.since(dose.time, now: now, in: timeZone)
                                + (dose.loggedByName.isEmpty ? "" : " by \(dose.loggedByName)")
                        },
                    ]))
                    .font(.subheadline)
                    .foregroundStyle(due ? Color.orange : Color.secondary)
                }
            }
            Button("Give") { router.sheet = .giveDose(medication.persistentModelID) }
                .buttonStyle(.bordered)
                .tint(due ? .orange : .accentColor)
        }
    }

    // MARK: Sections

    /// Two phones logging the same dose while apart is the double-dose that
    /// matters; say so plainly when a sync brings one in.
    @ViewBuilder
    private func duplicatesSection(medications: [Medication], doses: [MedicationDose], now: Date) -> some View {
        let recent = doses.filter { now.timeIntervalSince($0.time) < 48 * 3600 }
        let duplicates = MedicationSafety.possibleDuplicates(medications: medications, doses: recent)
        if let dose = duplicates.first {
            Section {
                Label {
                    Text("\(dose.medicationName) was logged twice close together, the second at \(ClockText.since(dose.time, now: now, in: timeZone))\(dose.loggedByName.isEmpty ? "" : " by \(dose.loggedByName)"). If it was only given once, delete the extra one.")
                        .font(.subheadline)
                } icon: {
                    Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
                }
                Button("Review") { router.sheet = .editEntry(.dose(dose.persistentModelID)) }
            }
        }
    }

    @ViewBuilder
    private func checkupSection(visits: [DoctorVisit], now: Date) -> some View {
        let birthDate = birthInterval > 0 ? Date(timeIntervalSince1970: birthInterval) : nil
        if let next = CheckupSchedule.next(birthDate: birthDate, visits: visits, now: now, calendar: calendar) {
            Section {
                Label(EntryRow.wrappingAtDots(CheckupSchedule.text(next, now: now, calendar: calendar)), systemImage: "calendar")
            } header: {
                Text("Next checkup")
            } footer: {
                if let source = FoodGuidance.source(CheckupSchedule.sourceID) {
                    Link("The AAP's schedule: the first week, then 1, 2, 4, 6, 9 and 12 months.", destination: source.url)
                        .font(.footnote)
                }
            }
        }
    }

    /// Breastfed babies need vitamin D drops; the amount comes from the
    /// pediatrician and the product, so it's left blank.
    @ViewBuilder
    private func vitaminDSection(medications: [Medication]) -> some View {
        let style = FeedingStyle(rawValue: feedingStyleRaw) ?? .formula
        let hasVitaminD = medications.contains { $0.name.localizedCaseInsensitiveContains("vitamin d") }
        if !vitaminDOfferDismissed, style != .formula, !hasVitaminD {
            Section {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Vitamin D")
                        .font(.headline)
                    Text("The AAP recommends 400 IU of vitamin D a day for babies who get breast milk, starting in the first few days. Ask your pediatrician which drops.")
                        .font(.subheadline)
                    if let source = FoodGuidance.source("aap-vitamin-d") {
                        Link("\(source.organisation): \(source.title)", destination: source.url)
                            .font(.footnote)
                    }
                    HStack {
                        Button("Add vitamin D") { router.sheet = .newMedication(vitaminD: true) }
                            .buttonStyle(.borderedProminent)
                        Button("Not now") { vitaminDOfferDismissed = true }
                            .buttonStyle(.bordered)
                    }
                }
                .padding(.vertical, 4)
            }
        }
    }

    private func notesSubtitle(notes: [CareNote], visits: [DoctorVisit], now: Date) -> String {
        let window = ReportWindow.defaultWindow(visits: visits, now: now, calendar: calendar)
        let start = window.start(now: now, calendar: calendar)
        let count = notes.writtenNotes.filter { $0.date >= start }.count
        guard case .since = window else {
            return count == 0 ? "Nothing this week" : "\(count) this week"
        }
        return count == 0 ? "None since the last visit" : "\(count) since the last visit"
    }
}
