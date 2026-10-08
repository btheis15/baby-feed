import SwiftData
import SwiftUI

/// The days with nothing logged, to mark the ones where everything was fine.
/// The charts then fill those days in with an estimate, faded and tagged
/// "est.", and the Timeline shows each one as a day marked fine, not logged.
struct FineDaysSheet: View {
    let babyID: UUID?

    @Environment(\.dismiss) private var dismiss
    @Environment(\.calendar) private var calendar
    @Environment(\.modelContext) private var modelContext
    @AppStorage(BabyProfile.birthDateKey) private var birthInterval: Double = 0

    @Query private var feeds: [FeedEntry]
    @Query private var diapers: [DiaperEntry]
    @Query private var notes: [CareNote]

    /// Three months back at most, like the longest chart.
    static let lookBackDays = 90

    init(babyID: UUID?) {
        self.babyID = babyID
        let id = babyID
        let start = Date.now.addingTimeInterval(-Double(Self.lookBackDays + 1) * 86_400)
        _feeds = Query(filter: #Predicate<FeedEntry> { $0.babyID == id && $0.deletedAt == nil && $0.startTime >= start })
        _diapers = Query(filter: #Predicate<DiaperEntry> { $0.babyID == id && $0.deletedAt == nil && $0.time >= start })
        let fine = CareNoteKind.allFine.rawValue
        _notes = Query(filter: #Predicate<CareNote> { $0.babyID == id && $0.deletedAt == nil && $0.kindRaw == fine })
    }

    private var days: [Date] {
        let today = calendar.startOfDay(for: .now)
        var start = calendar.date(byAdding: .day, value: -Self.lookBackDays, to: today) ?? today
        if birthInterval > 0 { start = max(start, calendar.startOfDay(for: Date(timeIntervalSince1970: birthInterval))) }
        // Nothing before the first thing ever logged: those days aren't
        // missing, the app just wasn't in use yet.
        let firstLogged = (feeds.map(\.startTime) + diapers.map(\.time)).min().map { calendar.startOfDay(for: $0) }
        guard let firstLogged else { return [] }
        start = max(start, firstLogged)
        return FineDays.unlogged(feeds: feeds, diapers: diapers, from: start, today: today, calendar: calendar)
    }

    var body: some View {
        let days = days
        let marked = FineDays.marked(notes, calendar: calendar)
        NavigationStack {
            List {
                if days.isEmpty {
                    ContentUnavailableView("No days to fill in", systemImage: "checkmark.circle",
                                           description: Text("Every day so far has something logged."))
                } else {
                    Section {
                        ForEach(days, id: \.self) { day in
                            Button {
                                toggle(day)
                            } label: {
                                HStack {
                                    Text(FeedStats.dayTitle(for: day, calendar: calendar))
                                        .foregroundStyle(Color.primary)
                                    Spacer()
                                    if marked.contains(day) {
                                        Label("Fine", systemImage: "checkmark.circle.fill")
                                            .foregroundStyle(.green)
                                    } else {
                                        Image(systemName: "circle")
                                            .foregroundStyle(.secondary)
                                    }
                                }
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .accessibilityAddTraits(marked.contains(day) ? .isSelected : [])
                        }
                    } footer: {
                        Text("Mark a day where everything was fine and the charts fill it in from the days around it, faded and marked est. Nothing is added to the log, and averages still count only the days that were logged.")
                    }

                    if days.contains(where: { !marked.contains($0) }) {
                        Section {
                            Button("Mark all as fine") {
                                for day in days where !marked.contains(day) { add(day) }
                                FeedCoordinator.feedsDidChange(in: modelContext)
                            }
                        }
                    }
                }
            }
            .navigationTitle("Days with nothing logged")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    private func toggle(_ day: Date) {
        if let existing = FineDays.mark(on: day, in: notes, calendar: calendar) {
            existing.softDelete()
        } else {
            add(day)
        }
        FeedCoordinator.feedsDidChange(in: modelContext)
    }

    private func add(_ day: Date) {
        modelContext.insert(FineDays.newMark(on: day, babyID: babyID, loggedByName: AppSettings.displayName,
                                             calendar: calendar))
    }
}

#Preview {
    FineDaysSheet(babyID: nil)
        .modelContainer(.preview)
}
