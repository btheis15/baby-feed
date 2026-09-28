import SwiftData
import SwiftUI

/// Logs something that isn't a feed – breathing, crying, a rash, a bad night.
/// One tap for the kind, a sentence, Save.
struct LogCareNoteSheet: View {
    enum Mode {
        case new
        /// An update on a concern ("less red today"), linked to it.
        case update(HealthConcern)
        case edit(CareNote)
    }

    let mode: Mode

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Environment(AppRouter.self) private var router
    @Environment(ToastCenter.self) private var toasts
    @AppStorage(AppSettings.currentBabyIDKey) private var currentBabyIDRaw = ""
    @AppStorage(BabyProfile.birthDateKey) private var birthInterval: Double = 0

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
        case .update(let concern):
            isEditing = false
            _kind = State(initialValue: concern.kind)
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

    /// Under 12 weeks, any fever means a call: the AAP's line, shown with a
    /// temperature note rather than left in a list somewhere.
    private var showsFeverFlag: Bool {
        guard kind == .temperature, birthInterval > 0 else { return false }
        let profile = BabyProfile(name: "", birthDate: Date(timeIntervalSince1970: birthInterval))
        return (profile.ageInDays(on: date, calendar: AppSettings.calendar) ?? 999) < 84
    }

    private var concernForUpdate: HealthConcern? {
        if case .update(let concern) = mode { return concern }
        return nil
    }

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

                if let concern = concernForUpdate {
                    Section {
                        Label("An update on \(concern.title)", systemImage: "link")
                            .font(.subheadline)
                    }
                }

                Section {
                    TextField(concernForUpdate == nil ? kind.placeholder : "Less red today, still goopy in the morning…",
                              text: $note, axis: .vertical)
                        .lineLimit(3...8)
                        .focused($noteFocused)
                } header: {
                    Text("What happened")
                } footer: {
                    Text("Write it however you'd say it out loud. This is the part the pediatrician actually reads.")
                }

                if showsFeverFlag, let flag = IntakeGuidance.redFlags.first(where: { $0.id == "fever" }),
                   let source = FoodGuidance.source("aap-fever-baby") {
                    Section {
                        Label {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(flag.text)
                                    .font(.subheadline.weight(.semibold))
                                Text("For a baby this young, 100.4 °F (38 °C) or higher, taken rectally, is a fever: call your pediatrician right away, even if they seem fine.")
                                    .font(.footnote)
                                Link(destination: source.url) {
                                    Text("\(source.organisation): \(source.title)")
                                        .font(.footnote)
                                }
                            }
                        } icon: {
                            Image(systemName: "phone.fill").foregroundStyle(.red)
                        }
                    }
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

                if case .edit(let careNote) = mode, careNote.concernID == nil {
                    Section {
                        Button {
                            router.sheet = .trackConcern(careNote.persistentModelID)
                        } label: {
                            Label("Track as a concern", systemImage: "cross.case")
                        }
                    } footer: {
                        Text("For something that's going on: it counts the days until you say it's better.")
                    }
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
        case .new, .update:
            let careNote = CareNote(
                babyID: UUID(uuidString: currentBabyIDRaw),
                date: date,
                kind: kind,
                note: trimmedNote,
                severity: kind.usesSeverity ? severity : nil,
                loggedByName: AppSettings.displayName
            )
            careNote.concernID = concernForUpdate?.uuid
            modelContext.insert(careNote)
            FeedCoordinator.feedsDidChange(in: modelContext)
            toasts.logged(.note(careNote), context: modelContext, router: router)
        case .edit(let careNote):
            careNote.date = date
            careNote.kind = kind
            careNote.note = trimmedNote
            careNote.severity = kind.usesSeverity ? severity : nil
            careNote.markChanged()
            FeedCoordinator.feedsDidChange(in: modelContext)
        }
        dismiss()
    }

    private func deleteCareNote() {
        if case .edit(let careNote) = mode {
            careNote.softDelete()
            FeedCoordinator.feedsDidChange(in: modelContext)
        }
        dismiss()
    }
}

#Preview {
    LogCareNoteSheet(mode: .new)
        .environment(AppRouter())
        .environment(ToastCenter())
        .modelContainer(.preview)
}
