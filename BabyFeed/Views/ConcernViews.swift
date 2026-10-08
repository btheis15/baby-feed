import SwiftData
import SwiftUI

/// Starting or editing a concern: what it is, since when, how bad.
struct LogConcernSheet: View {
    enum Mode {
        /// A new concern, optionally of a kind, and optionally from a note
        /// that turned out to be the start of something ("Track as a concern").
        case new(kind: CareNoteKind?, fromNote: CareNote?)
        case edit(HealthConcern)
    }

    let mode: Mode

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Environment(AppRouter.self) private var router
    @Environment(ToastCenter.self) private var toasts

    @State private var title = ""
    @State private var kind: CareNoteKind = .other
    @State private var startedAt = Date.now
    @State private var severity: CareNoteSeverity?
    @State private var note = ""
    @State private var isResolved = false
    @State private var resolvedAt = Date.now
    @State private var outcome = ""
    @State private var showDeleteConfirmation = false
    @State private var prefilled = false

    private var isEditing: Bool {
        if case .edit = mode { return true }
        return false
    }

    private var trimmedTitle: String { title.trimmingCharacters(in: .whitespacesAndNewlines) }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("What kind", selection: $kind) {
                        ForEach(CareNoteKind.pickable) { kind in
                            Label(kind.title, systemImage: kind.systemImage).tag(kind)
                        }
                    }
                    TextField("Red left eye, stuffy nose…", text: $title)
                        .textInputAutocapitalization(.sentences)
                } header: {
                    Text("What's going on")
                }

                Section {
                    DatePicker("Started", selection: $startedAt, in: ...Date.now, displayedComponents: [.date, .hourAndMinute])
                    if kind.usesSeverity {
                        Picker("At its worst", selection: $severity) {
                            Text("Not set").tag(CareNoteSeverity?.none)
                            ForEach(CareNoteSeverity.allCases) { level in
                                Text(level.title).tag(CareNoteSeverity?.some(level))
                            }
                        }
                    }
                } footer: {
                    Text("Backdate it to when it first showed: the doctor will ask how long it's been.")
                }

                Section("Notes") {
                    TextField(kind.placeholder, text: $note, axis: .vertical)
                        .lineLimit(2...6)
                }

                if isEditing {
                    Section {
                        Toggle("It's better", isOn: $isResolved.animation())
                        if isResolved {
                            DatePicker("Since", selection: $resolvedAt, in: startedAt...Date.now,
                                       displayedComponents: [.date, .hourAndMinute])
                            TextField("How it cleared up (optional)", text: $outcome)
                        }
                    }
                }
            }
            .navigationTitle(isEditing ? "Edit concern" : "New concern")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                        .disabled(trimmedTitle.isEmpty)
                }
                if isEditing {
                    ToolbarItem(placement: .destructiveAction) {
                        Button("Delete", role: .destructive) { showDeleteConfirmation = true }
                    }
                }
            }
            .confirmationDialog("Delete this concern?", isPresented: $showDeleteConfirmation, titleVisibility: .visible) {
                Button("Delete Concern", role: .destructive) { deleteConcern() }
            } message: {
                Text("Notes about it stay in the log.")
            }
            .onChange(of: kind) { old, new in
                // Follow the kind while the title is still the kind's own.
                if trimmedTitle.isEmpty || trimmedTitle == old.concernTitle { title = new.concernTitle }
                if !new.usesSeverity { severity = nil }
            }
            .onAppear(perform: prefill)
        }
    }

    private func prefill() {
        guard !prefilled else { return }
        prefilled = true
        switch mode {
        case .new(let kind, let note):
            let chosen = note?.kind ?? kind ?? .other
            self.kind = chosen
            title = chosen.concernTitle
            if let note {
                startedAt = note.date
                self.note = note.note
                severity = note.severity
            }
        case .edit(let concern):
            title = concern.title
            kind = concern.kind
            startedAt = concern.startedAt
            severity = concern.severity
            note = concern.note
            isResolved = concern.resolvedAt != nil
            resolvedAt = concern.resolvedAt ?? .now
            outcome = concern.outcome
        }
    }

    private func save() {
        let trimmedNote = note.trimmingCharacters(in: .whitespacesAndNewlines)
        switch mode {
        case .new(_, let fromNote):
            let concern = HealthConcern(
                babyID: AppSettings.currentBabyID,
                title: trimmedTitle,
                kind: kind,
                startedAt: startedAt,
                severity: kind.usesSeverity ? severity : nil,
                note: trimmedNote,
                loggedByName: AppSettings.displayName
            )
            modelContext.insert(concern)
            if let fromNote {
                fromNote.concernID = concern.uuid
                fromNote.markChanged()
            }
            FeedCoordinator.feedsDidChange(in: modelContext)
            toasts.logged(.concern(concern), context: modelContext, router: router)
        case .edit(let concern):
            concern.title = trimmedTitle
            concern.kind = kind
            concern.startedAt = startedAt
            concern.severity = kind.usesSeverity ? severity : nil
            concern.note = trimmedNote
            concern.resolvedAt = isResolved ? max(resolvedAt, startedAt) : nil
            concern.outcome = isResolved ? outcome.trimmingCharacters(in: .whitespacesAndNewlines) : ""
            concern.markChanged()
            FeedCoordinator.feedsDidChange(in: modelContext)
        }
        dismiss()
    }

    private func deleteConcern() {
        if case .edit(let concern) = mode {
            concern.softDelete()
            FeedCoordinator.feedsDidChange(in: modelContext)
        }
        dismiss()
    }
}

/// One concern, start to finish: how long it's been, its updates as a small
/// timeline, and "It's better" (or "Reopen").
struct ConcernDetailView: View {
    let concern: HealthConcern

    @Environment(\.modelContext) private var modelContext
    @Environment(\.calendar) private var calendar
    @Environment(\.timeZone) private var timeZone
    @Environment(AppRouter.self) private var router
    @Query(sort: \CareNote.date, order: .reverse) private var notes: [CareNote]

    @State private var showBetter = false

    var body: some View {
        let now = Date.now
        let updates = ConcernStats.updates(for: concern, in: notes)
        List {
            Section {
                VStack(alignment: .leading, spacing: 6) {
                    Label(concern.kind.title, systemImage: concern.kind.systemImage)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Text(ConcernStats.statusText(concern, now: now, calendar: calendar))
                        .font(.title3.weight(.semibold))
                    Text(ConcernStats.startedText(concern, now: now, calendar: calendar))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    if let severity = concern.severity {
                        Text("At its worst: \(severity.title.lowercased())")
                            .font(.subheadline)
                    }
                    if !concern.note.isEmpty {
                        Text(concern.note)
                            .font(.body)
                            .padding(.top, 4)
                    }
                    if !concern.outcome.isEmpty {
                        Text(concern.outcome)
                            .font(.body)
                            .foregroundStyle(.green)
                    }
                }
                .padding(.vertical, 4)

                if ConcernStats.needsCheckIn(concern, notes: notes, now: now, calendar: calendar) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Still going on?")
                            .font(.headline)
                        HStack {
                            Button("Yes, still") {
                                concern.markChanged()
                                FeedCoordinator.feedsDidChange(in: modelContext)
                            }
                            .buttonStyle(.bordered)
                            Button("It's better") { showBetter = true }
                                .buttonStyle(.borderedProminent)
                        }
                    }
                    .padding(.vertical, 4)
                }
            }

            Section {
                Button {
                    router.sheet = .newUpdate(concern.persistentModelID)
                } label: {
                    Label("Add an update", systemImage: "plus.bubble")
                }
                ForEach(updates) { update in
                    Button {
                        router.sheet = .editEntry(.note(update.persistentModelID))
                    } label: {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(update.note.isEmpty ? update.kind.title : update.note)
                                .foregroundStyle(.primary)
                            Text(EntryRow.joined([ClockText.since(update.date, now: now, in: timeZone),
                                                  LoggedBy.text(update.loggedByName)]))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .buttonStyle(.plain)
                }
            } header: {
                Text("Updates")
            } footer: {
                Text("Short notes as it changes (\"less red today\"), so the doctor can see how it went.")
            }

            Section {
                if concern.isOngoing {
                    Button("It's better") { showBetter = true }
                } else {
                    Button("Reopen") {
                        concern.resolvedAt = nil
                        concern.outcome = ""
                        concern.markChanged()
                        FeedCoordinator.feedsDidChange(in: modelContext)
                    }
                }
            }
        }
        .navigationTitle(concern.title.isEmpty ? concern.kind.title : concern.title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button("Edit") { router.sheet = .editEntry(.concern(concern.persistentModelID)) }
            }
        }
        .confirmationDialog("Better since when?", isPresented: $showBetter, titleVisibility: .visible) {
            Button("Now") { resolve(daysAgo: 0) }
            Button("Yesterday") { resolve(daysAgo: 1) }
            Button("2 days ago") { resolve(daysAgo: 2) }
            Button("Cancel", role: .cancel) {}
        }
    }

    private func resolve(daysAgo: Int) {
        let date = daysAgo == 0 ? Date.now : (calendar.date(byAdding: .day, value: -daysAgo, to: .now) ?? .now)
        concern.resolvedAt = max(date, concern.startedAt)
        concern.markChanged()
        FeedCoordinator.feedsDidChange(in: modelContext)
    }
}
