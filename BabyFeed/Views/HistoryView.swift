import SwiftUI
import SwiftData

/// Every feed, grouped by day with per-day totals.
struct HistoryView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \FeedEntry.startTime, order: .reverse) private var entries: [FeedEntry]
    @AppStorage(FeedDefaults.volumeUnit) private var unitRaw = VolumeUnit.ounces.rawValue

    @State private var editingEntry: FeedEntry?

    private var unit: VolumeUnit { VolumeUnit(rawValue: unitRaw) ?? .ounces }

    var body: some View {
        NavigationStack {
            Group {
                if entries.isEmpty {
                    ContentUnavailableView(
                        "No feeds yet",
                        systemImage: "list.bullet.clipboard",
                        description: Text("Feeds you log will show up here, grouped by day.")
                    )
                } else {
                    List {
                        ForEach(FeedStats.groupByDay(entries)) { group in
                            Section {
                                ForEach(group.entries) { entry in
                                    FeedRow(entry: entry, unit: unit)
                                        .contentShape(Rectangle())
                                        .onTapGesture { editingEntry = entry }
                                }
                                .onDelete { offsets in
                                    delete(offsets.map { group.entries[$0] })
                                }
                            } header: {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(FeedStats.dayTitle(for: group.day))
                                        .font(.headline)
                                        .foregroundStyle(.primary)
                                        .textCase(nil)
                                    Text(group.summary.text(unit: unit))
                                        .font(.subheadline)
                                        .textCase(nil)
                                }
                                .padding(.bottom, 4)
                            }
                        }
                    }
                    .listStyle(.insetGrouped)
                }
            }
            .navigationTitle("History")
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
    HistoryView()
        .modelContainer(for: FeedEntry.self, inMemory: true)
}
