import SwiftData
import SwiftUI

/// What's typed about a new baby, shared by onboarding and "Add a baby".
struct NewBabyDraft {
    var name = ""
    var birthDate = Date.now
    var sex: BabySex = .unspecified
    var bornEarly = false
    var dueDate = Date.now
    var poundsText = ""
    var ouncesText = ""
    var kilogramsText = ""

    var trimmedName: String { name.trimmingCharacters(in: .whitespacesAndNewlines) }

    /// Nil when nothing sensible was typed.
    func birthWeightGrams(in unit: WeightUnit) -> Double? {
        func number(_ text: String) -> Double? {
            Double(text.replacingOccurrences(of: ",", with: ".").trimmingCharacters(in: .whitespaces))
        }
        let grams: Double?
        switch unit {
        case .poundsOunces:
            guard let pounds = number(poundsText) else { return nil }
            grams = WeightUnit.grams(pounds: Int(pounds), ounces: number(ouncesText) ?? 0)
        case .kilograms:
            grams = number(kilogramsText).map { $0 * 1000 }
        }
        // Anywhere from a very early baby to a big one; outside that it's a typo.
        guard let grams, (300...7000).contains(grams) else { return nil }
        return grams
    }

    @MainActor
    @discardableResult
    func create(weightUnit: WeightUnit, in context: ModelContext) -> Baby {
        BabyStore.createBaby(
            name: trimmedName,
            birthDate: AppSettings.calendar.startOfDay(for: birthDate),
            sex: sex,
            dueDate: bornEarly ? dueDate : nil,
            birthWeightGrams: birthWeightGrams(in: weightUnit),
            in: context
        )
    }
}

/// The name, birthday, birth weight and growth-chart sections, for inside a Form.
struct NewBabyFields: View {
    @Binding var draft: NewBabyDraft
    let weightUnit: WeightUnit

    var body: some View {
        Section {
            TextField("Name", text: $draft.name)
                .textInputAutocapitalization(.words)
            DatePicker("Birthday", selection: $draft.birthDate, in: ...Date.now, displayedComponents: .date)
        } footer: {
            Text("The birthday sets what's typical to feed at each age.")
        }

        Section {
            birthWeightField
        } header: {
            Text("Birth weight (optional)")
        } footer: {
            Text("Most babies lose a little in the first days and are back by about two weeks. With a birth weight, the app can show that.")
        }

        Section {
            Picker("Sex", selection: $draft.sex) {
                ForEach(BabySex.allCases) { sex in
                    Text(sex.title).tag(sex)
                }
            }
            Toggle("Born before the due date", isOn: $draft.bornEarly.animation())
            if draft.bornEarly {
                DatePicker("Due date", selection: $draft.dueDate, displayedComponents: .date)
            }
        } header: {
            Text("For the growth charts (optional)")
        } footer: {
            Text("The WHO charts are measured separately for girls and boys, and a baby born early is compared at their corrected age.")
        }
    }

    @ViewBuilder
    private var birthWeightField: some View {
        switch weightUnit {
        case .poundsOunces:
            HStack {
                TextField("7", text: $draft.poundsText)
                    .keyboardType(.numberPad)
                    .frame(maxWidth: 60)
                Text("lb").foregroundStyle(.secondary)
                TextField("8", text: $draft.ouncesText)
                    .keyboardType(.decimalPad)
                    .frame(maxWidth: 60)
                Text("oz").foregroundStyle(.secondary)
                Spacer()
            }
        case .kilograms:
            HStack {
                TextField("3.40", text: $draft.kilogramsText)
                    .keyboardType(.decimalPad)
                Text("kg").foregroundStyle(.secondary)
            }
        }
    }
}

/// Another baby on this phone (a twin, a sibling, or a fresh one to test
/// with), from the Baby tab. It becomes the current baby.
struct AddBabySheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @AppStorage(AppSettings.weightUnitKey) private var weightUnitRaw = WeightUnit.poundsOunces.rawValue
    @State private var draft = NewBabyDraft()

    private var weightUnit: WeightUnit { WeightUnit(rawValue: weightUnitRaw) ?? .poundsOunces }

    var body: some View {
        NavigationStack {
            Form {
                NewBabyFields(draft: $draft, weightUnit: weightUnit)
            }
            .navigationTitle("Add a baby")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") { add() }
                        .disabled(draft.trimmedName.isEmpty)
                }
            }
        }
    }

    private func add() {
        draft.create(weightUnit: weightUnit, in: modelContext)
        // A phone already syncing backs the new baby up too. One that has
        // never connected stays that way: no Local Network prompt from here.
        if SyncCredentials.isPaired, !SyncCredentials.optedOut {
            Task { try? await SyncEngine.shared.ensureConnected(.addedBaby) }
        }
        dismiss()
    }
}

#Preview {
    AddBabySheet()
        .modelContainer(.preview)
}
