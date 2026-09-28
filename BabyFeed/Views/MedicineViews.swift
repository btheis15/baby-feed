import SwiftData
import SwiftUI

/// Setting up a medicine or supplement. Every number comes from the label or
/// the doctor, and all of them are optional: the app records what's given and
/// never suggests a dose.
struct MedicationSheet: View {
    enum Mode {
        case new(name: String, kind: MedicationKind, schedule: MedicationSchedule, unit: DoseUnit)
        case edit(Medication)

        static var blank: Mode { .new(name: "", kind: .medicine, schedule: .asNeeded, unit: .ml) }
    }

    let mode: Mode

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    @State private var name = ""
    @State private var kind: MedicationKind = .medicine
    @State private var amountText = ""
    @State private var unit: DoseUnit = .ml
    @State private var schedule: MedicationSchedule = .asNeeded
    @State private var timesPerDay = 1
    @State private var intervalHours = 4.0
    @State private var minHoursText = ""
    @State private var maxPerDayText = ""
    @State private var startDate = Date.now
    @State private var hasEnd = false
    @State private var endDate = Date.now.addingTimeInterval(7 * 86_400)
    @State private var instructions = ""
    @State private var showDeleteConfirmation = false
    @State private var prefilled = false

    private var isEditing: Bool {
        if case .edit = mode { return true }
        return false
    }

    private var trimmedName: String { name.trimmingCharacters(in: .whitespacesAndNewlines) }

    private func number(_ text: String) -> Double? {
        let value = Double(text.replacingOccurrences(of: ",", with: ".").trimmingCharacters(in: .whitespaces))
        return value.flatMap { $0 > 0 ? $0 : nil }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Name, as on the label", text: $name)
                        .textInputAutocapitalization(.words)
                    Picker("Kind", selection: $kind) {
                        ForEach(MedicationKind.allCases) { Text($0.title).tag($0) }
                    }
                }

                Section {
                    HStack {
                        TextField("Amount", text: $amountText)
                            .keyboardType(.decimalPad)
                        Picker("Unit", selection: $unit) {
                            ForEach(DoseUnit.allCases) { Text($0.title).tag($0) }
                        }
                        .labelsHidden()
                    }
                } header: {
                    Text("Dose (from the label or your doctor)")
                } footer: {
                    Text("Optional. Left blank, each dose is logged with whatever you give. Liquid medicine is measured in ml with the dropper or syringe it comes with, never a kitchen spoon.")
                }

                Section {
                    Picker("How often", selection: $schedule) {
                        ForEach(MedicationSchedule.allCases) { Text($0.title).tag($0) }
                    }
                    switch schedule {
                    case .daily:
                        Stepper("\(timesPerDay) time\(timesPerDay == 1 ? "" : "s") a day", value: $timesPerDay, in: 1...6)
                    case .everyNHours:
                        Stepper("Every \(intervalHours.formatted()) hours", value: $intervalHours, in: 1...24, step: 1)
                    case .asNeeded:
                        EmptyView()
                    }
                    HStack {
                        Text("At least")
                        TextField("–", text: $minHoursText)
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                            .frame(maxWidth: 60)
                        Text("hours apart")
                    }
                    HStack {
                        Text("No more than")
                        TextField("–", text: $maxPerDayText)
                            .keyboardType(.numberPad)
                            .multilineTextAlignment(.trailing)
                            .frame(maxWidth: 60)
                        Text("a day")
                    }
                } header: {
                    Text("Schedule")
                } footer: {
                    Text("The gaps and limit are for a gentle heads-up when logging. Fill them in only from the label or your doctor.")
                }

                Section {
                    DatePicker("Started", selection: $startDate, displayedComponents: .date)
                    Toggle("Ends", isOn: $hasEnd.animation())
                    if hasEnd {
                        DatePicker("Last day", selection: $endDate, in: startDate..., displayedComponents: .date)
                    }
                    TextField("Instructions (optional)", text: $instructions, axis: .vertical)
                        .lineLimit(1...4)
                }

                Section {
                } footer: {
                    Text(MedicationSafety.disclaimer)
                }
            }
            .navigationTitle(isEditing ? "Edit medicine" : "Add a medicine")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                        .disabled(trimmedName.isEmpty)
                }
                if isEditing {
                    ToolbarItem(placement: .destructiveAction) {
                        Button("Delete", role: .destructive) { showDeleteConfirmation = true }
                    }
                }
            }
            .confirmationDialog("Delete this medicine?", isPresented: $showDeleteConfirmation, titleVisibility: .visible) {
                Button("Delete Medicine", role: .destructive) { deleteMedication() }
            } message: {
                Text("Doses already logged stay in the log.")
            }
            .onAppear(perform: prefill)
        }
    }

    private func prefill() {
        guard !prefilled else { return }
        prefilled = true
        switch mode {
        case .new(let name, let kind, let schedule, let unit):
            self.name = name
            self.kind = kind
            self.schedule = schedule
            self.unit = unit
        case .edit(let medication):
            name = medication.name
            kind = medication.kind
            amountText = medication.doseAmount.map { $0.formatted(.number.precision(.fractionLength(0...2)).grouping(.never)) } ?? ""
            unit = medication.doseUnit
            schedule = medication.schedule
            timesPerDay = medication.timesPerDay ?? 1
            intervalHours = medication.intervalHours ?? 4
            minHoursText = medication.minHoursBetween.map { $0.formatted() } ?? ""
            maxPerDayText = medication.maxDosesPer24h.map(String.init) ?? ""
            startDate = medication.startDate
            hasEnd = medication.endDate != nil
            endDate = medication.endDate ?? endDate
            instructions = medication.instructions
        }
    }

    private func save() {
        let medication: Medication
        switch mode {
        case .new:
            medication = Medication(babyID: AppSettings.currentBabyID, name: trimmedName, loggedByName: AppSettings.displayName)
            modelContext.insert(medication)
        case .edit(let existing):
            medication = existing
        }
        medication.name = trimmedName
        medication.kind = kind
        medication.doseAmount = number(amountText)
        medication.doseUnit = unit
        medication.schedule = schedule
        medication.timesPerDay = schedule == .daily ? timesPerDay : nil
        medication.intervalHours = schedule == .everyNHours ? intervalHours : nil
        medication.minHoursBetween = number(minHoursText)
        medication.maxDosesPer24h = number(maxPerDayText).map { Int($0) }
        medication.startDate = AppSettings.calendar.startOfDay(for: startDate)
        medication.endDate = hasEnd ? endDate : nil
        medication.instructions = instructions.trimmingCharacters(in: .whitespacesAndNewlines)
        medication.markChanged()
        FeedCoordinator.feedsDidChange(in: modelContext)
        dismiss()
    }

    private func deleteMedication() {
        if case .edit(let medication) = mode {
            medication.softDelete()
            FeedCoordinator.feedsDidChange(in: modelContext)
        }
        dismiss()
    }
}

/// Logging a dose. It checks with the other phone first, so a dose Annette
/// gave at 2:30 is here before anyone gives another, and says what it found:
/// too soon, the day's limit, already given. Those are notices, never locks:
/// Save stays, and reads "Log anyway".
struct LogDoseSheet: View {
    enum Mode {
        case new(Medication?)
        case edit(MedicationDose)
    }

    let mode: Mode

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Environment(\.calendar) private var calendar
    @Environment(\.timeZone) private var timeZone
    @Environment(AppRouter.self) private var router
    @Environment(ToastCenter.self) private var toasts
    @Query(sort: \Medication.name) private var medications: [Medication]
    @Query(sort: \MedicationDose.time, order: .reverse) private var doses: [MedicationDose]
    @AppStorage(AppSettings.currentBabyIDKey) private var currentBabyIDRaw = ""

    @State private var medicationID: PersistentIdentifier?
    @State private var freeName = ""
    @State private var amountText = ""
    @State private var unit: DoseUnit = .ml
    @State private var time = Date.now
    @State private var note = ""
    @State private var checkedWithOtherPhone: Bool?
    @State private var showDeleteConfirmation = false
    @State private var prefilled = false

    private var isEditing: Bool {
        if case .edit = mode { return true }
        return false
    }

    private var babyMedications: [Medication] {
        medications.active(for: UUID(uuidString: currentBabyIDRaw))
    }

    private var medication: Medication? {
        medicationID.flatMap { id in babyMedications.first { $0.persistentModelID == id } }
    }

    private var name: String {
        (medication?.name ?? freeName).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var notices: [MedicationSafety.Notice] {
        guard !isEditing, let medication else { return [] }
        return MedicationSafety.notices(for: medication, doses: doses.active(for: UUID(uuidString: currentBabyIDRaw)),
                                        loggingAs: AppSettings.displayName, now: time, calendar: calendar)
    }

    var body: some View {
        NavigationStack {
            Form {
                if let checkedWithOtherPhone {
                    Section {
                        Label(checkedWithOtherPhone
                              ? "Checked with the other phone just now."
                              : "Couldn't reach your Mac mini: a dose logged on the other phone may not be here yet.",
                              systemImage: checkedWithOtherPhone ? "checkmark.icloud" : "icloud.slash")
                            .font(.footnote)
                            .foregroundStyle(checkedWithOtherPhone ? Color.secondary : Color.orange)
                    }
                }

                Section {
                    if !babyMedications.isEmpty {
                        Picker("Medicine", selection: $medicationID) {
                            Text("Something else").tag(PersistentIdentifier?.none)
                            ForEach(babyMedications) { medication in
                                Text(medication.name).tag(PersistentIdentifier?.some(medication.persistentModelID))
                            }
                        }
                    }
                    if medication == nil {
                        TextField("What was given", text: $freeName)
                            .textInputAutocapitalization(.words)
                    }
                    if let last = medication.flatMap({ MedicationStats.lastDose(of: $0, in: doses) }) {
                        Text("Last given \(ClockText.since(last.time, now: .now, in: timeZone))\(last.loggedByName.isEmpty ? "" : " by \(last.loggedByName)")")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }

                Section {
                    HStack {
                        TextField("Amount", text: $amountText)
                            .keyboardType(.decimalPad)
                        Picker("Unit", selection: $unit) {
                            ForEach(DoseUnit.allCases) { Text($0.title).tag($0) }
                        }
                        .labelsHidden()
                    }
                    DatePicker("When", selection: $time, in: ...Date.now.addingTimeInterval(60),
                               displayedComponents: [.date, .hourAndMinute])
                    TextField("Note (optional)", text: $note)
                } header: {
                    Text("Given")
                } footer: {
                    Text(medication?.doseAmount == nil
                         ? "The amount you gave, from the label or your doctor."
                         : "The amount set for this medicine. Change it if you gave something different.")
                }

                if !notices.isEmpty {
                    Section {
                        ForEach(notices) { notice in
                            Label(text(for: notice), systemImage: "exclamationmark.circle")
                                .font(.subheadline)
                                .foregroundStyle(.orange)
                        }
                    } footer: {
                        Text("A heads-up, not a rule: if your doctor said otherwise, log it anyway.")
                    }
                }

                Section {
                } footer: {
                    Text(MedicationSafety.disclaimer)
                }
            }
            .navigationTitle(isEditing ? "Edit dose" : "Give a medicine")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(notices.isEmpty ? "Save" : "Log anyway") { save() }
                        .disabled(name.isEmpty)
                }
                if isEditing {
                    ToolbarItem(placement: .destructiveAction) {
                        Button("Delete", role: .destructive) { showDeleteConfirmation = true }
                    }
                }
            }
            .confirmationDialog("Delete this dose?", isPresented: $showDeleteConfirmation, titleVisibility: .visible) {
                Button("Delete Dose", role: .destructive) { deleteDose() }
            }
            .onAppear(perform: prefill)
            .onChange(of: medicationID) { _, _ in
                // A different medicine brings its own amount, or none.
                guard !isEditing else { return }
                apply(DoseDraft.initial(for: medication))
            }
            .task { await checkWithOtherPhone() }
        }
    }

    private func text(for notice: MedicationSafety.Notice) -> String {
        switch notice {
        case .tooSoon(let last, let minHours):
            return "Last given \(ClockText.since(last, now: .now, in: timeZone)); the label or your doctor said at least \(minHours.formatted()) hours apart."
        case .dailyMaxReached(let count, let max):
            return "\(count) given in the last 24 hours; the limit you set is \(max)."
        case .alreadyGivenToday(let at, let by):
            return "Already given today at \(ClockText.time(at, in: timeZone))\(by.isEmpty ? "" : " by \(by)")."
        case .courseEnded(let date):
            return "The course ended on \(date.formatted(Date.FormatStyle(date: .abbreviated, time: .omitted, timeZone: timeZone)))."
        case .recentByOtherCaregiver(let at, let by):
            return "\(by) gave it at \(ClockText.time(at, in: timeZone))."
        }
    }

    private func apply(_ draft: DoseDraft) {
        amountText = draft.amount.map { $0.formatted(.number.precision(.fractionLength(0...2)).grouping(.never)) } ?? ""
        unit = draft.unit
    }

    private func prefill() {
        guard !prefilled else { return }
        prefilled = true
        switch mode {
        case .new(let medication):
            medicationID = medication?.persistentModelID
            apply(DoseDraft.initial(for: medication))
        case .edit(let dose):
            medicationID = babyMedications.first { $0.uuid == dose.medicationID }?.persistentModelID
            freeName = dose.medicationName
            amountText = dose.amount.map { $0.formatted(.number.precision(.fractionLength(0...2)).grouping(.never)) } ?? ""
            unit = dose.unit ?? .ml
            time = dose.time
            note = dose.note
        }
    }

    /// A sync first, so a dose given on the other phone is here before this
    /// one is logged. Says plainly when it couldn't check.
    private func checkWithOtherPhone() async {
        guard !isEditing, SyncCredentials.isPaired else { return }
        await SyncEngine.shared.syncNow()
        if case .idle = SyncEngine.shared.status {
            checkedWithOtherPhone = true
        } else {
            checkedWithOtherPhone = false
        }
    }

    private func save() {
        let amount = Double(amountText.replacingOccurrences(of: ",", with: ".").trimmingCharacters(in: .whitespaces))
            .flatMap { $0 > 0 ? $0 : nil }
        let trimmedNote = note.trimmingCharacters(in: .whitespacesAndNewlines)
        switch mode {
        case .new:
            let dose = MedicationDose(
                babyID: AppSettings.currentBabyID,
                medicationID: medication?.uuid,
                medicationName: name,
                time: time,
                amount: amount,
                unit: unit,
                note: trimmedNote,
                loggedByName: AppSettings.displayName
            )
            modelContext.insert(dose)
            FeedCoordinator.feedsDidChange(in: modelContext)
            toasts.logged(.dose(dose), detail: dose.amountText, context: modelContext, router: router)
        case .edit(let dose):
            dose.medicationID = medication?.uuid ?? dose.medicationID
            dose.medicationName = name
            dose.amount = amount
            dose.unit = unit
            dose.time = time
            dose.note = trimmedNote
            dose.markChanged()
            FeedCoordinator.feedsDidChange(in: modelContext)
        }
        dismiss()
    }

    private func deleteDose() {
        if case .edit(let dose) = mode {
            dose.softDelete()
            FeedCoordinator.feedsDidChange(in: modelContext)
        }
        dismiss()
    }
}

/// One medicine: its schedule, when it was last given and by whom, and its
/// doses.
struct MedicationDetailView: View {
    let medication: Medication

    @Environment(\.calendar) private var calendar
    @Environment(\.timeZone) private var timeZone
    @Environment(\.modelContext) private var modelContext
    @Environment(AppRouter.self) private var router
    @Environment(ToastCenter.self) private var toasts
    @Query(sort: \MedicationDose.time, order: .reverse) private var doses: [MedicationDose]

    var body: some View {
        let mine = MedicationStats.doses(of: medication, in: doses)
        List {
            Section {
                LabeledContent("How often", value: MedicationDetailView.scheduleText(medication))
                if let amount = medication.doseAmount {
                    LabeledContent("Dose", value: DoseUnit.format(amount, unit: medication.doseUnit))
                }
                if let minHours = medication.minHoursBetween {
                    LabeledContent("At least", value: "\(minHours.formatted()) h apart")
                }
                if let max = medication.maxDosesPer24h {
                    LabeledContent("No more than", value: "\(max) a day")
                }
                if let end = medication.endDate {
                    LabeledContent("Until", value: end.formatted(Date.FormatStyle(date: .abbreviated, time: .omitted, timeZone: timeZone)))
                }
                if !medication.instructions.isEmpty {
                    Text(medication.instructions).font(.subheadline)
                }
                Button {
                    router.sheet = .giveDose(medication.persistentModelID)
                } label: {
                    Label("Give now", systemImage: "plus.circle.fill")
                }
            } footer: {
                Text(MedicationSafety.disclaimer)
            }

            Section("Given") {
                if mine.isEmpty {
                    Text("Nothing logged yet").foregroundStyle(.secondary)
                }
                ForEach(mine) { dose in
                    Button {
                        router.sheet = .editEntry(.dose(dose.persistentModelID))
                    } label: {
                        TimelineRow(item: .dose(dose), unit: .milliliters, weightUnit: .kilograms, showsDay: true)
                    }
                    .buttonStyle(.plain)
                    .swipeActions {
                        Button(role: .destructive) {
                            toasts.delete(.dose(dose), context: modelContext)
                        } label: {
                            Label("Delete", systemImage: "trash")
                        }
                    }
                }
            }
        }
        .navigationTitle(medication.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button("Edit") { router.sheet = .editEntry(.medication(medication.persistentModelID)) }
            }
        }
    }

    static func scheduleText(_ medication: Medication) -> String {
        switch medication.schedule {
        case .asNeeded: "As needed"
        case .daily:
            (medication.timesPerDay ?? 1) == 1 ? "Once a day" : "\(medication.timesPerDay ?? 1) times a day"
        case .everyNHours: "Every \((medication.intervalHours ?? 0).formatted()) hours"
        }
    }
}
