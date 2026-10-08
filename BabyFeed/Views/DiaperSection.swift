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
        // The tap logs it now; a long press picks a time, for the change
        // that's logged after the fact.
        .contextMenu {
            Button {
                router.sheet = .logDiaper(kind)
            } label: {
                Label("Log at another time…", systemImage: "clock")
            }
        }
        .accessibilityAction(named: "Log at another time") { router.sheet = .logDiaper(kind) }
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

/// A diaper at a time other than now – changed in the night and logged in the
/// morning – or fixing a stray tap. The one-tap buttons stay the fast path; this
/// is behind a long press on them, the quick menu, and Edit.
struct LogDiaperSheet: View {
    enum Mode {
        case new(DiaperKind)
        case edit(DiaperEntry)
    }

    let mode: Mode

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Environment(AppRouter.self) private var router
    @Environment(ToastCenter.self) private var toasts

    @State private var kind: DiaperKind
    @State private var time: Date
    @State private var showDeleteConfirmation = false

    private static let timeChips = [0, 15, 30, 60]

    init(mode: Mode) {
        self.mode = mode
        switch mode {
        case .new(let kind):
            _kind = State(initialValue: kind)
            _time = State(initialValue: .now)
        case .edit(let entry):
            _kind = State(initialValue: entry.kind)
            _time = State(initialValue: entry.time)
        }
    }

    private var isEditing: Bool {
        if case .edit = mode { return true }
        return false
    }

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
                }

                Section("When") {
                    HStack(spacing: 8) {
                        ForEach(Self.timeChips, id: \.self) { minutesBack in
                            let selected = abs(minutesAgo - minutesBack) <= 1
                            Button {
                                time = Date.now.addingTimeInterval(-Double(minutesBack) * 60)
                            } label: {
                                Text(Self.chipLabel(minutesBack))
                                    .font(.subheadline.weight(.semibold))
                                    .lineLimit(1)
                                    .minimumScaleFactor(0.8)
                                    .padding(.vertical, 8)
                                    .frame(maxWidth: .infinity)
                                    .background(selected ? kind.color : Color(.tertiarySystemFill), in: Capsule())
                                    .foregroundStyle(selected ? Color.white : Color.primary)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    DatePicker("Exact time", selection: $time, in: ...Date.now.addingTimeInterval(60))
                }
            }
            .navigationTitle(isEditing ? "Edit diaper" : "Log diaper")
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
            .confirmationDialog("Delete this diaper?", isPresented: $showDeleteConfirmation, titleVisibility: .visible) {
                Button("Delete Diaper", role: .destructive) {
                    if case .edit(let entry) = mode {
                        entry.softDelete()
                        FeedCoordinator.feedsDidChange(in: modelContext)
                    }
                    dismiss()
                }
            }
        }
        .presentationDetents([.medium])
    }

    private var minutesAgo: Int {
        Int(Date.now.timeIntervalSince(time) / 60)
    }

    static func chipLabel(_ minutesBack: Int) -> String {
        switch minutesBack {
        case 0: "Now"
        case 60: "1 hr ago"
        default: "\(minutesBack) min ago"
        }
    }

    private func save() {
        switch mode {
        case .new:
            let entry = DiaperEntry(
                babyID: AppSettings.currentBabyID,
                time: time,
                kind: kind,
                loggedByName: AppSettings.displayName
            )
            modelContext.insert(entry)
            FeedCoordinator.feedsDidChange(in: modelContext)
            toasts.logged(.diaper(entry), context: modelContext, router: router)
        case .edit(let entry):
            entry.kind = kind
            entry.time = time
            entry.markChanged()
            FeedCoordinator.feedsDidChange(in: modelContext)
        }
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
