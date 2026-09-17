import SwiftUI
import SwiftData

struct SettingsView: View {
    @Query private var entries: [FeedEntry]
    @AppStorage(FeedDefaults.volumeUnit) private var unitRaw = VolumeUnit.ounces.rawValue
    @AppStorage(FeedDefaults.amountKey(for: .formula)) private var formulaML: Double = 0
    @AppStorage(FeedDefaults.amountKey(for: .breastMilk)) private var breastMilkML: Double = 0

    private var unit: VolumeUnit { VolumeUnit(rawValue: unitRaw) ?? .ounces }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("Units", selection: $unitRaw) {
                        ForEach(VolumeUnit.allCases) { unit in
                            Text(unit.title).tag(unit.rawValue)
                        }
                    }
                    .pickerStyle(.inline)
                    .labelsHidden()
                } header: {
                    Text("Units")
                } footer: {
                    Text("Amounts are stored precisely, so you can switch units any time.")
                }

                Section {
                    amountStepper("Formula", ml: $formulaML)
                    amountStepper("Breast milk", ml: $breastMilkML)
                } header: {
                    Text("Default amounts")
                } footer: {
                    Text("Each feed you save becomes the next default, so you rarely need to change these by hand.")
                }

                Section {
                    ShareLink(item: FeedStats.csv(entries, unit: unit), subject: Text("Baby Feed log")) {
                        Label("Export as CSV", systemImage: "square.and.arrow.up")
                    }
                    .disabled(entries.isEmpty)
                } header: {
                    Text("Export")
                } footer: {
                    Text(entries.isEmpty
                         ? "Log a feed first, then you can export your history."
                         : "\(entries.count) feeds. Handy for the pediatrician.")
                }

                Section("About") {
                    LabeledContent("Version", value: appVersion)
                    Text("Feeds are stored only on this device. No account, no cloud.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Settings")
        }
    }

    private var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
    }

    private func amountStepper(_ title: String, ml: Binding<Double>) -> some View {
        let currentML = ml.wrappedValue > 0 ? ml.wrappedValue : unit.toMilliliters(unit.defaultAmount)
        let current = unit.rounded(unit.fromMilliliters(currentML))

        return Stepper(
            onIncrement: {
                ml.wrappedValue = unit.toMilliliters(min(unit.maximum, current + unit.step))
            },
            onDecrement: {
                ml.wrappedValue = unit.toMilliliters(max(unit.step, current - unit.step))
            }
        ) {
            HStack {
                Text(title)
                Spacer()
                Text(unit.format(milliliters: currentML))
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
        }
    }
}

#Preview {
    SettingsView()
        .modelContainer(for: FeedEntry.self, inMemory: true)
}
