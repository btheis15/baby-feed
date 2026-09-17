import SwiftData
import SwiftUI

struct AddWeightSheet: View {
    let weightUnit: WeightUnit

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @State private var date: Date = .now
    @State private var pounds = 7
    @State private var ounces = 8
    @State private var kilogramsText = "3.4"
    @State private var note = ""

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
            .navigationTitle("Add Weight")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                        .disabled(grams == nil)
                }
            }
            .onAppear(perform: prefillFromLatest)
        }
        .presentationDetents([.medium, .large])
    }

    private func prefillFromLatest() {
        var fetch = FetchDescriptor<WeightEntry>(sortBy: [SortDescriptor(\.date, order: .reverse)])
        fetch.fetchLimit = 1
        guard let latest = try? modelContext.fetch(fetch).first else { return }
        let split = WeightUnit.poundsAndOunces(grams: latest.grams)
        pounds = split.pounds
        ounces = split.ounces
        kilogramsText = (latest.grams / 1000).formatted(.number.precision(.fractionLength(2)).locale(Locale(identifier: "en_US_POSIX")))
    }

    private func save() {
        guard let grams else { return }
        let entry = WeightEntry(date: date, grams: grams, note: note.trimmingCharacters(in: .whitespacesAndNewlines))
        modelContext.insert(entry)
        FeedCoordinator.settingsDidChange(in: modelContext)
        dismiss()
    }
}

#Preview {
    AddWeightSheet(weightUnit: .poundsOunces)
        .modelContainer(for: [FeedEntry.self, WeightEntry.self], inMemory: true)
}
