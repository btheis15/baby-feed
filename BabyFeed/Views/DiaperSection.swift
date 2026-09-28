import SwiftData
import SwiftUI

/// Diapers on the Today screen: three one-tap buttons and the day's tally.
///
/// A diaper change is the highest-frequency event in the house and carries no
/// amount, so unlike a feed it doesn't open a sheet: the tap is the log. The
/// toast that follows has Undo for a wrong tap, rather than a confirmation
/// that would slow down the other hundred taps that were right.
struct DiaperSection: View {
    /// The newest change for this baby, if any.
    let last: DiaperEntry?
    /// The last 24 hours, worked out by Today so that it and the Last 24
    /// hours card show the same numbers.
    let tally: DiaperTally

    @Environment(\.modelContext) private var modelContext
    @Environment(\.timeZone) private var timeZone
    @Environment(AppRouter.self) private var router
    @Environment(ToastCenter.self) private var toasts
    @AppStorage(AppSettings.currentBabyIDKey) private var currentBabyIDRaw = ""

    /// Flashes the tapped kind briefly, so a tap visibly landed.
    @State private var justLogged: DiaperKind?
    /// The last tap, so a double tap doesn't log two changes.
    @State private var lastTap: (kind: DiaperKind, at: Date)?

    /// A second tap on the same button inside this is taken as a bounce, not
    /// a second diaper. A real second change is never this quick.
    static let repeatTapWindow: TimeInterval = 1.5

    private var currentBabyID: UUID? { UUID(uuidString: currentBabyIDRaw) }

    var body: some View {
        VStack(spacing: 12) {
            HStack(spacing: 12) {
                ForEach(DiaperKind.allCases) { kind in
                    diaperButton(kind)
                }
            }

            HStack(alignment: .firstTextBaseline) {
                Text(EntryRow.wrappingAtDots(statusText))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                Spacer(minLength: 8)
                if last != nil {
                    Button("All diapers") {
                        router.openTimeline(filter: .only(.diapers))
                    }
                    .font(.footnote)
                }
            }
            // Clear of the section's rounded corners, which clip anything
            // sitting right at the row's edge.
            .padding(.horizontal, 14)
        }
    }

    /// "Last diaper 1:55 PM · 24 h: 5 wet · 2 dirty".
    private var statusText: String {
        guard let last else { return "No diapers logged yet" }
        let lastText = "Last diaper \(ClockText.since(last.time, now: .now, in: timeZone))"
        return tally.isEmpty ? "\(lastText) · none in 24 h" : "\(lastText) · 24 h: \(tally.text)"
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
        .accessibilityLabel("Log \(kind.entryTitle.lowercased())")
    }

    private func log(_ kind: DiaperKind) {
        let tappedAt = Date.now
        if let lastTap, lastTap.kind == kind, tappedAt.timeIntervalSince(lastTap.at) < Self.repeatTapWindow {
            return
        }
        lastTap = (kind, tappedAt)

        let entry = DiaperEntry(
            babyID: currentBabyID,
            time: tappedAt,
            kind: kind,
            loggedByName: AppSettings.displayName
        )
        modelContext.insert(entry)
        FeedCoordinator.feedsDidChange(in: modelContext)
        toasts.logged(.diaper(entry), context: modelContext, router: router)

        withAnimation { justLogged = kind }
        Task {
            try? await Task.sleep(for: .seconds(1.2))
            withAnimation { if justLogged == kind { justLogged = nil } }
        }
    }
}

/// Fixing a stray tap: the kind, the time, delete. Nothing else to a diaper.
struct EditDiaperSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    let entry: DiaperEntry

    @State private var kind: DiaperKind = .wet
    @State private var time: Date = .now
    @State private var showDeleteConfirmation = false

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
                ToolbarItem(placement: .destructiveAction) {
                    Button("Delete", role: .destructive) { showDeleteConfirmation = true }
                }
            }
            .confirmationDialog("Delete this diaper?", isPresented: $showDeleteConfirmation, titleVisibility: .visible) {
                Button("Delete Diaper", role: .destructive) {
                    entry.softDelete()
                    FeedCoordinator.feedsDidChange(in: modelContext)
                    dismiss()
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
        FeedCoordinator.feedsDidChange(in: modelContext)
        dismiss()
    }
}

#Preview {
    NavigationStack {
        List {
            Section("Diapers") { DiaperSection(last: nil, tally: DiaperTally([])) }
        }
    }
    .environment(AppRouter())
    .environment(ToastCenter())
    .modelContainer(.preview)
}
