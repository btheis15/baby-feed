import SwiftUI
import SwiftData

/// Sheet for logging a new feed or editing an existing one.
/// Pre-fills everything so the common case is just "tap Save".
struct LogFeedSheet: View {
    enum Mode {
        case new(FeedKind)
        case edit(FeedEntry)
    }

    let mode: Mode

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @AppStorage(FeedDefaults.volumeUnit) private var unitRaw = VolumeUnit.ounces.rawValue

    @State private var kind: FeedKind
    /// Bottle amount in the display unit (oz or ml).
    @State private var amount: Double
    @State private var minutes: Int
    @State private var side: NursingSide?
    @State private var time: Date
    @State private var note: String
    @State private var showDeleteConfirmation = false

    private let isEditing: Bool
    private var unit: VolumeUnit { VolumeUnit(rawValue: unitRaw) ?? .ounces }

    private static let timeChips = [0, 15, 30, 60]
    private static let nursingChips = [5, 10, 15, 20, 30, 45]

    init(mode: Mode) {
        self.mode = mode
        let unit = VolumeUnit(rawValue: UserDefaults.standard.string(forKey: FeedDefaults.volumeUnit) ?? "") ?? .ounces

        switch mode {
        case .new(let kind):
            isEditing = false
            _kind = State(initialValue: kind)
            _amount = State(initialValue: Self.defaultAmount(for: kind, unit: unit))
            _minutes = State(initialValue: FeedDefaults.defaultNursingMinutes())
            _side = State(initialValue: nil)
            _time = State(initialValue: .now)
            _note = State(initialValue: "")
        case .edit(let entry):
            isEditing = true
            _kind = State(initialValue: entry.kind)
            let amount = entry.amountML.map { unit.rounded(unit.fromMilliliters($0)) }
                ?? Self.defaultAmount(for: entry.kind, unit: unit)
            _amount = State(initialValue: amount)
            _minutes = State(initialValue: entry.durationMinutes ?? FeedDefaults.defaultNursingMinutes())
            _side = State(initialValue: entry.side)
            _time = State(initialValue: entry.startTime)
            _note = State(initialValue: entry.note)
        }
    }

    private static func defaultAmount(for kind: FeedKind, unit: VolumeUnit) -> Double {
        let bottleKind: FeedKind = kind.usesVolume ? kind : .formula
        return unit.rounded(unit.fromMilliliters(FeedDefaults.defaultAmountML(for: bottleKind, unit: unit)))
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 28) {
                    Picker("Kind", selection: $kind) {
                        ForEach(FeedKind.allCases) { kind in
                            Text(kind.title).tag(kind)
                        }
                    }
                    .pickerStyle(.segmented)

                    if kind.usesVolume {
                        amountSection
                    } else {
                        nursingSection
                    }

                    timeSection
                    noteSection
                }
                .padding()
            }
            .scrollDismissesKeyboard(.interactively)
            .safeAreaInset(edge: .bottom) {
                saveButton
                    .padding()
                    .background(.bar)
            }
            .navigationTitle(isEditing ? "Edit Feed" : "Log \(kind.title)")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                if isEditing {
                    ToolbarItem(placement: .destructiveAction) {
                        Button("Delete", role: .destructive) { showDeleteConfirmation = true }
                    }
                }
            }
            .confirmationDialog("Delete this feed?", isPresented: $showDeleteConfirmation, titleVisibility: .visible) {
                Button("Delete Feed", role: .destructive) { deleteEntry() }
            }
            .onChange(of: kind) { _, newKind in
                // Switching bottle kinds on a new entry picks up that kind's usual amount.
                if !isEditing, newKind.usesVolume {
                    amount = Self.defaultAmount(for: newKind, unit: unit)
                }
            }
        }
    }

    // MARK: Sections

    private var amountSection: some View {
        VStack(spacing: 16) {
            sectionTitle("Amount")

            HStack(spacing: 20) {
                stepButton("minus") {
                    amount = max(0, unit.rounded(amount - unit.step))
                }
                VStack(spacing: 0) {
                    Text(unit.formatValue(amount))
                        .font(.system(size: 56, weight: .bold, design: .rounded))
                        .monospacedDigit()
                        .contentTransition(.numericText())
                    Text(unit.symbol)
                        .font(.title3)
                        .foregroundStyle(.secondary)
                }
                .frame(minWidth: 130)
                stepButton("plus") {
                    amount = min(unit.maximum, unit.rounded(amount + unit.step))
                }
            }
            .frame(maxWidth: .infinity)
            .animation(.snappy, value: amount)

            chips(unit.presets,
                  isSelected: { abs($0 - amount) < 0.001 },
                  label: { unit.formatValue($0) }) { amount = $0 }
        }
    }

    private var nursingSection: some View {
        VStack(spacing: 16) {
            sectionTitle("Duration")

            HStack(spacing: 20) {
                stepButton("minus") {
                    minutes = max(1, minutes - 5)
                }
                VStack(spacing: 0) {
                    Text("\(minutes)")
                        .font(.system(size: 56, weight: .bold, design: .rounded))
                        .monospacedDigit()
                        .contentTransition(.numericText())
                    Text("min")
                        .font(.title3)
                        .foregroundStyle(.secondary)
                }
                .frame(minWidth: 130)
                stepButton("plus") {
                    minutes = min(120, minutes + 5)
                }
            }
            .frame(maxWidth: .infinity)
            .animation(.snappy, value: minutes)

            chips(Self.nursingChips,
                  isSelected: { $0 == minutes },
                  label: { "\($0) min" }) { minutes = $0 }

            sectionTitle("Side")
            chips(NursingSide.allCases,
                  isSelected: { $0 == side },
                  label: { $0.title }) { tapped in
                side = (side == tapped) ? nil : tapped
            }
        }
    }

    private var timeSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionTitle("When")

            chips(Self.timeChips,
                  isSelected: { abs(minutesAgo - $0) <= 1 },
                  label: { timeChipLabel($0) }) { minutesBack in
                time = Date.now.addingTimeInterval(-Double(minutesBack) * 60)
            }

            DatePicker(
                "Exact time",
                selection: $time,
                in: ...Date.now.addingTimeInterval(60),
                displayedComponents: [.date, .hourAndMinute]
            )
            .padding(12)
            .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
    }

    private var noteSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionTitle("Note")
            TextField("Optional – spit up, fussy, took a while…", text: $note, axis: .vertical)
                .lineLimit(1...3)
                .padding(12)
                .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
    }

    private var saveButton: some View {
        Button(action: save) {
            Text(isEditing ? "Save Changes" : "Save")
                .font(.title3.weight(.semibold))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 6)
        }
        .buttonStyle(.borderedProminent)
        .controlSize(.large)
        .tint(kind.color)
    }

    // MARK: Pieces

    private var minutesAgo: Int {
        Int(Date.now.timeIntervalSince(time) / 60)
    }

    private func timeChipLabel(_ minutesBack: Int) -> String {
        switch minutesBack {
        case 0: "Now"
        case 60: "1 hr ago"
        default: "\(minutesBack) min ago"
        }
    }

    private func sectionTitle(_ text: String) -> some View {
        Text(text)
            .font(.subheadline.weight(.medium))
            .foregroundStyle(.secondary)
            .textCase(.uppercase)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func stepButton(_ symbol: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.title.weight(.bold))
                .frame(width: 64, height: 64)
                .background(kind.color.opacity(0.15), in: Circle())
                .foregroundStyle(kind.color)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(symbol == "plus" ? "Increase" : "Decrease")
    }

    private func chips<T: Hashable>(
        _ values: [T],
        isSelected: @escaping (T) -> Bool,
        label: @escaping (T) -> String,
        action: @escaping (T) -> Void
    ) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(values, id: \.self) { value in
                    let selected = isSelected(value)
                    Button {
                        action(value)
                    } label: {
                        Text(label(value))
                            .font(.body.weight(.semibold))
                            .padding(.horizontal, 16)
                            .padding(.vertical, 10)
                            .background(selected ? kind.color : Color(.tertiarySystemFill), in: Capsule())
                            .foregroundStyle(selected ? Color.white : Color.primary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 2)
        }
    }

    // MARK: Actions

    private func save() {
        let amountML: Double? = kind.usesVolume ? unit.toMilliliters(amount) : nil
        let duration: Int? = kind.usesVolume ? nil : minutes
        let nursingSide: NursingSide? = kind.usesVolume ? nil : side
        let trimmedNote = note.trimmingCharacters(in: .whitespacesAndNewlines)

        switch mode {
        case .new:
            let entry = FeedEntry(
                startTime: time,
                kind: kind,
                amountML: amountML,
                durationMinutes: duration,
                side: nursingSide,
                note: trimmedNote
            )
            modelContext.insert(entry)
        case .edit(let entry):
            entry.startTime = time
            entry.kind = kind
            entry.amountML = amountML
            entry.durationMinutes = duration
            entry.side = nursingSide
            entry.note = trimmedNote
        }

        // What you just saved becomes the next default.
        if let amountML {
            FeedDefaults.setDefaultAmountML(amountML, for: kind)
        } else {
            FeedDefaults.setDefaultNursingMinutes(minutes)
        }

        try? modelContext.save()
        dismiss()
    }

    private func deleteEntry() {
        if case .edit(let entry) = mode {
            modelContext.delete(entry)
            try? modelContext.save()
        }
        dismiss()
    }
}

#Preview("New formula") {
    LogFeedSheet(mode: .new(.formula))
        .modelContainer(for: FeedEntry.self, inMemory: true)
}

#Preview("New nursing") {
    LogFeedSheet(mode: .new(.nursing))
        .modelContainer(for: FeedEntry.self, inMemory: true)
}
