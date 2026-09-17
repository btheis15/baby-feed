import SwiftUI
import SwiftData

/// The main screen: time since last feed, 24-hour totals, big log buttons,
/// and the recent feeds. Everything a tired parent needs at a glance.
struct HomeView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \FeedEntry.startTime, order: .reverse) private var entries: [FeedEntry]
    @AppStorage(FeedDefaults.volumeUnit) private var unitRaw = VolumeUnit.ounces.rawValue

    @State private var newFeedKind: FeedKind?
    @State private var editingEntry: FeedEntry?

    private var unit: VolumeUnit { VolumeUnit(rawValue: unitRaw) ?? .ounces }

    var body: some View {
        NavigationStack {
            // Re-renders every 30 seconds so the "time since" counter stays live.
            TimelineView(.periodic(from: .now, by: 30)) { context in
                let now = context.date
                let recent = FeedStats.entries(entries, within: 24 * 60 * 60, now: now)

                List {
                    Section {
                        LastFedCard(lastFeed: entries.first, unit: unit, now: now)
                    }

                    Section {
                        SummaryCard(title: "Last 24 hours", summary: FeedSummary(recent), unit: unit)
                    }

                    Section {
                        QuickLogButtons(unit: unit) { kind in
                            newFeedKind = kind
                        }
                        .listRowBackground(Color.clear)
                        .listRowInsets(EdgeInsets())
                    }

                    if !recent.isEmpty {
                        Section("Recent feeds") {
                            ForEach(recent) { entry in
                                FeedRow(entry: entry, unit: unit)
                                    .contentShape(Rectangle())
                                    .onTapGesture { editingEntry = entry }
                            }
                            .onDelete { offsets in
                                delete(offsets.map { recent[$0] })
                            }
                        }
                    }
                }
                .listStyle(.insetGrouped)
            }
            .navigationTitle("Baby Feed")
            .sheet(item: $newFeedKind) { kind in
                LogFeedSheet(mode: .new(kind))
            }
            .sheet(item: $editingEntry) { entry in
                LogFeedSheet(mode: .edit(entry))
            }
        }
    }

    private func delete(_ toDelete: [FeedEntry]) {
        withAnimation {
            for entry in toDelete {
                modelContext.delete(entry)
            }
        }
    }
}

#Preview {
    HomeView()
        .modelContainer(for: FeedEntry.self, inMemory: true)
}
