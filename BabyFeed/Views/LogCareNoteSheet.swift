import SwiftData
import SwiftUI

/// Logs something that isn't a feed – breathing, crying, a rash, a bad night.
/// One tap for the kind, a sentence, Save.
struct LogCareNoteSheet: View {
    enum Mode {
        case new
        case edit(CareNote)
    }

    let mode: Mode

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @AppStorage(AppSettings.currentBabyIDKey) private var currentBabyIDRaw = ""

    @State private var kind: CareNoteKind
    @State private var note: String
    @State private var severity: CareNoteSeverity?
    @State private var date: Date
    @State private var showDeleteConfirmation = false
    @FocusState private var noteFocused: Bool

    private let isEditing: Bool

    init(mode: Mode) {
        self.mode = mode
        switch mode {
        case .new:
            isEditing = false
            _kind = State(initialValue: .other)
            _note = State(initialValue: "")
            _severity = State(initialValue: nil)
            _date = State(initialValue: .now)
        case .edit(let careNote):
            isEditing = true
            _kind = State(initialValue: careNote.kind)
            _note = State(initialValue: careNote.note)
            _severity = State(initialValue: careNote.severity)
            _date = State(initialValue: careNote.date)
        }
    }

    private var trimmedNote: String { note.trimmingCharacters(in: .whitespacesAndNewlines) }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("What kind", selection: $kind) {
                        ForEach(CareNoteKind.allCases) { kind in
                            Label(kind.title, systemImage: kind.systemImage).tag(kind)
                        }
                    }
                } footer: {
                    Text("Pick the closest kind – it's only there to group things in the report.")
                }

                Section {
                    TextField(kind.placeholder, text: $note, axis: .vertical)
                        .lineLimit(3...8)
                        .focused($noteFocused)
                } header: {
                    Text("What happened")
                } footer: {
                    Text("Write it however you'd say it out loud. This is the part the pediatrician actually reads.")
                }

                if kind.usesSeverity {
                    Section {
                        Picker("How bad", selection: $severity) {
                            Text("Not saying").tag(CareNoteSeverity?.none)
                            ForEach(CareNoteSeverity.allCases) { level in
                                Text(level.title).tag(CareNoteSeverity?.some(level))
                            }
                        }
                        .pickerStyle(.segmented)
                    }
                }

                Section {
                    DatePicker("When", selection: $date, in: ...Date.now)
                } footer: {
                    Text("Backdate it if you're catching up – that's the normal case.")
                }
            }
            .navigationTitle(isEditing ? "Edit note" : "Add a note")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                        .disabled(trimmedNote.isEmpty)
                }
                if isEditing {
                    ToolbarItem(placement: .destructiveAction) {
                        Button("Delete", role: .destructive) { showDeleteConfirmation = true }
                    }
                }
            }
            .confirmationDialog("Delete this note?", isPresented: $showDeleteConfirmation, titleVisibility: .visible) {
                Button("Delete Note", role: .destructive) { deleteCareNote() }
            }
            .onAppear { noteFocused = !isEditing }
            .onChange(of: kind) { _, newKind in
                // Severity is meaningless for some kinds; don't carry a stale one.
                if !newKind.usesSeverity { severity = nil }
            }
        }
    }

    private func save() {
        switch mode {
        case .new:
            let careNote = CareNote(
                babyID: UUID(uuidString: currentBabyIDRaw),
                date: date,
                kind: kind,
                note: trimmedNote,
                severity: kind.usesSeverity ? severity : nil,
                loggedByName: AppSettings.displayName
            )
            modelContext.insert(careNote)
        case .edit(let careNote):
            careNote.date = date
            careNote.kind = kind
            careNote.note = trimmedNote
            careNote.severity = kind.usesSeverity ? severity : nil
            careNote.markChanged()
        }
        FeedCoordinator.careNotesDidChange(in: modelContext)
        dismiss()
    }

    private func deleteCareNote() {
        if case .edit(let careNote) = mode {
            FeedCoordinator.delete(careNote, in: modelContext)
        }
        dismiss()
    }
}

#Preview {
    LogCareNoteSheet(mode: .new)
        .modelContainer(for: [FeedEntry.self, WeightEntry.self, Baby.self, CareNote.self], inMemory: true)
}
