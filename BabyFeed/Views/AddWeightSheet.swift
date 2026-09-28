import SwiftData
import SwiftUI

struct AddWeightSheet: View {
    enum Mode {
        case new
        case edit(WeightEntry)
    }

    let weightUnit: WeightUnit
    var mode: Mode = .new
    /// For "Add birth weight": the birthday, and a note saying what it is.
    var initialDate: Date? = nil
    var initialNote: String = ""

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Environment(AppRouter.self) private var router
    @Environment(ToastCenter.self) private var toasts

    @State private var date: Date = .now
    @State private var pounds = 7
    @State private var ounces = 8
    @State private var kilogramsText = "3.4"
    @State private var note = ""
    @State private var showDeleteConfirmation = false
    /// What the weight controls showed when an edit opened. Saving without
    /// touching them keeps the stored grams exactly: the wheels only go to the
    /// ounce, and reading the weight back off them would quietly round it.
    @State private var initialControls: Controls?

    private struct Controls: Equatable {
        var pounds: Int
        var ounces: Int
        var kilograms: String
    }

    private var controls: Controls { Controls(pounds: pounds, ounces: ounces, kilograms: kilogramsText) }

    private var isEditing: Bool {
        if case .edit = mode { return true }
        return false
    }

    private var grams: Double? {
        switch weightUnit {
        case .poundsOunces:
            return WeightUnit.grams(pounds: pounds, ounces: Double(ounces))
        case .kilograms:
            let normalized = kilogramsText.replacingOccurrences(of: ",", with: ".")
            guard let kg = Double(normalized), kg > 0 else { return nil }
            return kg * 1000
        }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    DatePicker("Date", selection: $date, in: ...Date.now, displayedComponents: .date)
                }

                Section("Weight") {
                    switch weightUnit {
                    case .poundsOunces:
                        HStack(spacing: 0) {
                            Picker("Pounds", selection: $pounds) {
                                ForEach(0...25, id: \.self) { value in
                                    Text("\(value) lb").tag(value)
                                }
                            }
                            .pickerStyle(.wheel)
                            .frame(maxWidth: .infinity)
                            Picker("Ounces", selection: $ounces) {
                                ForEach(0...15, id: \.self) { value in
                                    Text("\(value) oz").tag(value)
                                }
                            }
                            .pickerStyle(.wheel)
                            .frame(maxWidth: .infinity)
                        }
                        .frame(height: 150)
                    case .kilograms:
                        HStack {
                            TextField("Kilograms", text: $kilogramsText)
                                .keyboardType(.decimalPad)
                                .font(.title2.weight(.semibold))
                            Text("kg")
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                Section {
                    TextField("Note (optional) – e.g. pediatrician visit", text: $note)
                }
            }
            .navigationTitle(isEditing ? "Edit Weight" : (initialNote.isEmpty ? "Add Weight" : initialNote))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                        .disabled(grams == nil)
                }
                if isEditing {
                    ToolbarItem(placement: .destructiveAction) {
                        Button("Delete", role: .destructive) { showDeleteConfirmation = true }
                    }
                }
            }
            .confirmationDialog("Delete this weight?", isPresented: $showDeleteConfirmation, titleVisibility: .visible) {
                Button("Delete Weight", role: .destructive) { deleteEntry() }
            }
            .onAppear(perform: prefill)
        }
        .presentationDetents([.medium, .large])
    }

    private func prefill() {
        let source: WeightEntry
        switch mode {
        case .edit(let entry):
            source = entry
            date = entry.date
            note = entry.note
        case .new:
            if let initialDate { date = initialDate }
            if !initialNote.isEmpty { note = initialNote }
            // Start the wheels at the last weigh-in: the new one is close by.
            let fetch = FetchDescriptor<WeightEntry>(sortBy: [SortDescriptor(\.date, order: .reverse)])
            let all = (try? modelContext.fetch(fetch)) ?? []
            guard let latest = all.active(for: AppSettings.currentBabyID).first else { return }
            source = latest
        }
        let split = WeightUnit.poundsAndOunces(grams: source.grams)
        let kilograms = (source.grams / 1000).formatted(.number.precision(.fractionLength(2)).locale(Locale(identifier: "en_US_POSIX")))
        pounds = split.pounds
        ounces = split.ounces
        kilogramsText = kilograms
        if isEditing {
            initialControls = Controls(pounds: split.pounds, ounces: split.ounces, kilograms: kilograms)
        }
    }

    private func save() {
        guard let grams else { return }
        let trimmedNote = note.trimmingCharacters(in: .whitespacesAndNewlines)
        switch mode {
        case .new:
            let entry = WeightEntry(
                babyID: AppSettings.currentBabyID,
                date: date,
                grams: grams,
                note: trimmedNote,
                loggedByName: AppSettings.displayName
            )
            modelContext.insert(entry)
            FeedCoordinator.settingsDidChange(in: modelContext)
            toasts.logged(.weight(entry), detail: weightUnit.format(grams: grams), context: modelContext, router: router)
        case .edit(let entry):
            entry.date = date
            if controls != initialControls {
                entry.grams = grams
            }
            entry.note = trimmedNote
            entry.markChanged()
            FeedCoordinator.settingsDidChange(in: modelContext)
        }
        dismiss()
    }

    private func deleteEntry() {
        if case .edit(let entry) = mode {
            FeedCoordinator.delete(entry, in: modelContext)
        }
        dismiss()
    }
}

#Preview {
    AddWeightSheet(weightUnit: .poundsOunces)
        .environment(AppRouter())
        .environment(ToastCenter())
        .modelContainer(.preview)
}
