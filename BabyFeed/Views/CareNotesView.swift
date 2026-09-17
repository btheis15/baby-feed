import SwiftData
import SwiftUI

/// Everything logged that isn't a feed or a weight, newest first.
///
/// Exists so the appointment doesn't rely on memory: by the time you're in the
/// room, "she was snuffly for two days around the 9th" is gone unless it was
/// written down.
struct CareNotesView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.calendar) private var calendar
    @Query(sort: \CareNote.date, order: .reverse) private var allCareNotes: [CareNote]
    @AppStorage(AppSettings.currentBabyIDKey) private var currentBabyIDRaw = ""

    @State private var adding = false
    @State private var editing: CareNote?

    let babyName: String

    private var careNotes: [CareNote] {
        allCareNotes.active(for: UUID(uuidString: currentBabyIDRaw))
    }

    var body: some View {
        Group {
            if careNotes.isEmpty {
                ContentUnavailableView {
                    Label("No notes yet", systemImage: "note.text")
                } description: {
                    Text("Anything you'd want to mention at the next appointment – breathing, crying, a rash, a bad night. You won't remember it in three weeks; this will.")
                } actions: {
                    Button("Add a note") { adding = true }
                        .buttonStyle(.borderedProminent)
                }
            } else {
                List {
                    ForEach(careNotes) { careNote in
                        Button {
                            editing = careNote
                        } label: {
                            row(careNote)
                        }
                        .buttonStyle(.plain)
                    }
                    .onDelete(perform: delete)
                }
            }
        }
        .navigationTitle("Notes")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    adding = true
                } label: {
                    Label("Add a note", systemImage: "plus")
                }
            }
        }
        .sheet(isPresented: $adding) {
            LogCareNoteSheet(mode: .new)
        }
        .sheet(item: $editing) { careNote in
            LogCareNoteSheet(mode: .edit(careNote))
        }
    }

    private func row(_ careNote: CareNote) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline) {
                Label(careNote.kind.title, systemImage: careNote.kind.systemImage)
                    .font(.subheadline.weight(.medium))
                Spacer(minLength: 8)
                Text(careNote.date.formatted(date: .abbreviated, time: .shortened))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            if !careNote.note.isEmpty {
                Text(careNote.note)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            HStack(spacing: 6) {
                if let severity = careNote.severity {
                    Text(severity.title)
                        .foregroundStyle(severity == .severe ? .orange : .secondary)
                }
                if !careNote.loggedByName.isEmpty {
                    Text(severity_separator(careNote) + "Logged by \(careNote.loggedByName)")
                        .foregroundStyle(.secondary)
                }
            }
            .font(.caption)
        }
        .padding(.vertical, 2)
        .contentShape(Rectangle())
    }

    /// Keeps "Moderate · Brian" from reading as "ModerateBrian".
    private func severity_separator(_ careNote: CareNote) -> String {
        careNote.severity == nil ? "" : "· "
    }

    private func delete(at offsets: IndexSet) {
        let visible = careNotes
        withAnimation {
            for index in offsets {
                visible[index].softDelete()
            }
        }
        try? modelContext.save()
        SyncEngine.shared.requestSync()
    }
}

#Preview {
    NavigationStack {
        CareNotesView(babyName: "Nora")
    }
    .modelContainer(for: [FeedEntry.self, WeightEntry.self, Baby.self, CareNote.self], inMemory: true)
}
