import SwiftData
import SwiftUI

/// Diapers on the Today screen: three one-tap buttons and the day's tally.
///
/// A diaper change is the highest-frequency event in the house and carries no
/// amount, so unlike a feed it doesn't open a sheet — the tap is the log. A
/// wrong tap is fixed from the list behind "All diapers", not prevented with a
/// confirmation that would slow down the other hundred taps that were right.
struct DiaperSection: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \DiaperEntry.time, order: .reverse) private var diapers: [DiaperEntry]
    @AppStorage(AppSettings.currentBabyIDKey) private var currentBabyIDRaw = ""

    /// Flashes the tapped kind briefly, so a tap visibly landed.
    @State private var justLogged: DiaperKind?

    private var currentBabyID: UUID? { UUID(uuidString: currentBabyIDRaw) }

    var body: some View {
        let visible = diapers.active(for: currentBabyID)
        let last24h = visible.within(24 * 60 * 60)
        let tally = DiaperTally(last24h)

        VStack(spacing: 12) {
            HStack(spacing: 12) {
                ForEach(DiaperKind.allCases) { kind in
                    diaperButton(kind)
                }
            }

            HStack {
                Text(tally.isEmpty ? "No diapers in the last 24 h" : "Last 24 h: \(tally.text)")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                Spacer()
                if !visible.isEmpty {
                    NavigationLink {
                        DiaperListView()
                    } label: {
                        Text("All diapers")
                            .font(.footnote)
                    }
                }
            }
            .padding(.horizontal, 4)
        }
    }

    private func diaperButton(_ kind: DiaperKind) -> some View {
        Button {
            log(kind)
        } label: {
            VStack(spacing: 5) {
                Image(systemName: justLogged == kind ? "checkmark" : kind.systemImage)
                    .font(.system(size: 22))
                    .contentTransition(.symbolEffect(.replace))
                Text(kind.title)
                    .font(.subheadline.weight(.medium))
            }
            .frame(maxWidth: .infinity, minHeight: 64)
            .background(kind.color.opacity(0.15), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .foregroundStyle(kind.color)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Log \(kind.title.lowercased()) diaper")
    }

    private func log(_ kind: DiaperKind) {
        let entry = DiaperEntry(
            babyID: currentBabyID,
            kind: kind,
            loggedByName: AppSettings.displayName
        )
        modelContext.insert(entry)
        try? modelContext.save()
        SyncEngine.shared.requestSync()

        withAnimation { justLogged = kind }
        Task {
            try? await Task.sleep(for: .seconds(1.2))
            withAnimation { if justLogged == kind { justLogged = nil } }
        }
    }
}

/// Every diaper, newest first — where a stray tap gets fixed and where you
/// check whether anyone changed one during the night.
struct DiaperListView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.calendar) private var calendar
    @Query(sort: \DiaperEntry.time, order: .reverse) private var diapers: [DiaperEntry]
    @AppStorage(AppSettings.currentBabyIDKey) private var currentBabyIDRaw = ""

    @State private var editing: DiaperEntry?

    private var currentBabyID: UUID? { UUID(uuidString: currentBabyIDRaw) }

    var body: some View {
        let visible = diapers.active(for: currentBabyID)
        let groups = Dictionary(grouping: visible) { calendar.startOfDay(for: $0.time) }
            .sorted { $0.key > $1.key }

        List {
            ForEach(groups, id: \.key) { day, entries in
                Section {
                    ForEach(entries) { entry in
                        row(entry)
                            .contentShape(Rectangle())
                            .onTapGesture { editing = entry }
                    }
                    .onDelete { offsets in
                        delete(offsets.map { entries[$0] })
                    }
                } header: {
                    Text("\(FeedStats.dayTitle(for: day, calendar: calendar)) — \(DiaperTally(entries).text)")
                }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("Diapers")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: $editing) { entry in
            EditDiaperSheet(entry: entry)
        }
        .overlay {
            if visible.isEmpty {
                ContentUnavailableView(
                    "No diapers yet",
                    systemImage: "drop.halffull",
                    description: Text("Log one from the Today screen — a single tap.")
                )
            }
        }
    }

    private func row(_ entry: DiaperEntry) -> some View {
        HStack(spacing: 12) {
            Image(systemName: entry.kind.systemImage)
                .foregroundStyle(entry.kind.color)
                .frame(width: 26)
            VStack(alignment: .leading, spacing: 2) {
                Text(entry.kind.title)
                    .font(.body)
                if !entry.loggedByName.isEmpty {
                    Text("Logged by \(entry.loggedByName)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
            Text(entry.time.formatted(date: .omitted, time: .shortened))
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .monospacedDigit()
        }
    }

    private func delete(_ toDelete: [DiaperEntry]) {
        withAnimation {
            for entry in toDelete { entry.softDelete() }
        }
        try? modelContext.save()
        SyncEngine.shared.requestSync()
    }
}

/// Fixing a stray tap: the kind, the time, delete. Nothing else to a diaper.
struct EditDiaperSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    let entry: DiaperEntry

    @State private var kind: DiaperKind = .wet
    @State private var time: Date = .now

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("Kind", selection: $kind) {
                        ForEach(DiaperKind.allCases) { kind in
                            Text(kind.title).tag(kind)
                        }
                    }
                    .pickerStyle(.segmented)

                    DatePicker("When", selection: $time, in: ...Date.now)
                }

                Section {
                    Button("Delete", role: .destructive) {
                        entry.softDelete()
                        try? modelContext.save()
                        SyncEngine.shared.requestSync()
                        dismiss()
                    }
                }
            }
            .navigationTitle("Edit diaper")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                }
            }
            .onAppear {
                kind = entry.kind
                time = entry.time
            }
        }
        .presentationDetents([.medium])
    }

    private func save() {
        entry.kind = kind
        entry.time = time
        entry.markChanged()
        try? modelContext.save()
        SyncEngine.shared.requestSync()
        dismiss()
    }
}

#Preview {
    NavigationStack {
        List {
            Section("Diapers") { DiaperSection() }
        }
    }
    .modelContainer(for: [FeedEntry.self, WeightEntry.self, Baby.self, CareNote.self, DiaperEntry.self], inMemory: true)
}
