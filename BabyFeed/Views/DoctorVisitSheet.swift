import SwiftData
import SwiftUI

/// A doctor visit and what was said. A weight taken there becomes a weigh-in
/// linked to the visit, so the growth numbers and the birth-weight line use
/// it without anyone typing it twice.
struct DoctorVisitSheet: View {
    enum Mode {
        case new
        case edit(DoctorVisit)
    }

    let mode: Mode

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Environment(AppRouter.self) private var router
    @Environment(ToastCenter.self) private var toasts
    @AppStorage(AppSettings.weightUnitKey) private var weightUnitRaw = WeightUnit.poundsOunces.rawValue

    @State private var date = Date.now
    @State private var kind: VisitKind = .checkup
    @State private var provider = ""
    @State private var reason = ""
    @State private var doctorNotes = ""
    @State private var hasFollowUp = false
    @State private var followUpDate = Date.now.addingTimeInterval(14 * 86_400)
    @State private var followUpNote = ""
    @State private var vaccines = ""
    @State private var poundsText = ""
    @State private var ouncesText = ""
    @State private var kilogramsText = ""
    @State private var showDeleteConfirmation = false
    @State private var prefilled = false

    private var weightUnit: WeightUnit { WeightUnit(rawValue: weightUnitRaw) ?? .poundsOunces }

    private var isEditing: Bool {
        if case .edit = mode { return true }
        return false
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    DatePicker("When", selection: $date, in: ...Date.now.addingTimeInterval(86_400 * 365),
                               displayedComponents: [.date, .hourAndMinute])
                    Picker("Kind", selection: $kind) {
                        ForEach(VisitKind.allCases) { Text($0.title).tag($0) }
                    }
                    TextField("Doctor or clinic", text: $provider)
                        .textInputAutocapitalization(.words)
                    TextField("Why (1-week weight check, cough…)", text: $reason)
                }

                Section {
                    TextField("What the doctor said", text: $doctorNotes, axis: .vertical)
                        .lineLimit(3...10)
                } header: {
                    Text("What the doctor said")
                }

                Section {
                    switch weightUnit {
                    case .poundsOunces:
                        HStack {
                            TextField("lb", text: $poundsText).keyboardType(.numberPad).frame(maxWidth: 60)
                            Text("lb").foregroundStyle(.secondary)
                            TextField("oz", text: $ouncesText).keyboardType(.decimalPad).frame(maxWidth: 60)
                            Text("oz").foregroundStyle(.secondary)
                            Spacer()
                        }
                    case .kilograms:
                        HStack {
                            TextField("kg", text: $kilogramsText).keyboardType(.decimalPad)
                            Text("kg").foregroundStyle(.secondary)
                        }
                    }
                    TextField("Vaccines given (optional)", text: $vaccines)
                } header: {
                    Text("Weight and shots")
                } footer: {
                    Text("A weight here is also saved as a weigh-in.")
                }

                Section {
                    Toggle("Follow-up", isOn: $hasFollowUp.animation())
                    if hasFollowUp {
                        DatePicker("Around", selection: $followUpDate, displayedComponents: .date)
                        TextField("What for", text: $followUpNote)
                    }
                }
            }
            .navigationTitle(isEditing ? "Edit visit" : "Doctor visit")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                }
                if isEditing {
                    ToolbarItem(placement: .destructiveAction) {
                        Button("Delete", role: .destructive) { showDeleteConfirmation = true }
                    }
                }
            }
            .confirmationDialog("Delete this visit?", isPresented: $showDeleteConfirmation, titleVisibility: .visible) {
                Button("Delete Visit", role: .destructive) { deleteVisit() }
            } message: {
                Text("A weight saved with it stays as a weigh-in.")
            }
            .onAppear(perform: prefill)
        }
    }

    /// Nil when nothing sensible was typed.
    private var grams: Double? {
        func number(_ text: String) -> Double? {
            Double(text.replacingOccurrences(of: ",", with: ".").trimmingCharacters(in: .whitespaces))
        }
        let value: Double?
        switch weightUnit {
        case .poundsOunces:
            guard let pounds = number(poundsText) else { return nil }
            value = WeightUnit.grams(pounds: Int(pounds), ounces: number(ouncesText) ?? 0)
        case .kilograms:
            value = number(kilogramsText).map { $0 * 1000 }
        }
        guard let value, (300...30000).contains(value) else { return nil }
        return value
    }

    private func linkedWeight(_ visit: DoctorVisit) -> WeightEntry? {
        guard let id = visit.weightEntryID else { return nil }
        let descriptor = FetchDescriptor<WeightEntry>(predicate: #Predicate { $0.uuid == id })
        return (try? modelContext.fetch(descriptor))?.first
    }

    private func prefill() {
        guard !prefilled else { return }
        prefilled = true
        guard case .edit(let visit) = mode else { return }
        date = visit.date
        kind = visit.kind
        provider = visit.provider
        reason = visit.reason
        doctorNotes = visit.doctorNotes
        hasFollowUp = visit.followUpDate != nil
        followUpDate = visit.followUpDate ?? followUpDate
        followUpNote = visit.followUpNote
        vaccines = visit.vaccines
        if let weight = linkedWeight(visit), weight.deletedAt == nil {
            let split = WeightUnit.poundsAndOunces(grams: weight.grams)
            poundsText = "\(split.pounds)"
            ouncesText = "\(split.ounces)"
            kilogramsText = (weight.grams / 1000).formatted(.number.precision(.fractionLength(2)).grouping(.never))
        }
    }

    private func save() {
        let visit: DoctorVisit
        switch mode {
        case .new:
            visit = DoctorVisit(babyID: AppSettings.currentBabyID, loggedByName: AppSettings.displayName)
            modelContext.insert(visit)
        case .edit(let existing):
            visit = existing
        }
        visit.date = date
        visit.kind = kind
        visit.provider = provider.trimmingCharacters(in: .whitespacesAndNewlines)
        visit.reason = reason.trimmingCharacters(in: .whitespacesAndNewlines)
        visit.doctorNotes = doctorNotes.trimmingCharacters(in: .whitespacesAndNewlines)
        visit.followUpDate = hasFollowUp ? followUpDate : nil
        visit.followUpNote = hasFollowUp ? followUpNote.trimmingCharacters(in: .whitespacesAndNewlines) : ""
        visit.vaccines = vaccines.trimmingCharacters(in: .whitespacesAndNewlines)

        // The weight becomes (or updates) the weigh-in linked to this visit.
        if let grams {
            if let weight = linkedWeight(visit), weight.deletedAt == nil {
                if abs(weight.grams - grams) >= 1 || weight.date != date {
                    weight.grams = grams
                    weight.date = date
                    weight.markChanged()
                }
            } else {
                let weight = WeightEntry(babyID: visit.babyID, date: date, grams: grams,
                                         note: [visit.kind.title, visit.provider].filter { !$0.isEmpty }.joined(separator: " · "),
                                         loggedByName: AppSettings.displayName)
                modelContext.insert(weight)
                visit.weightEntryID = weight.uuid
            }
        }
        visit.markChanged()
        FeedCoordinator.feedsDidChange(in: modelContext)
        if case .new = mode {
            toasts.logged(.visit(visit), context: modelContext, router: router)
        }
        dismiss()
    }

    private func deleteVisit() {
        if case .edit(let visit) = mode {
            visit.softDelete()
            FeedCoordinator.feedsDidChange(in: modelContext)
        }
        dismiss()
    }
}
