import SwiftData
import SwiftUI

/// Every feed, grouped by day with a 24-hour strip per day, plus trends.
struct HistoryView: View {
    private enum Mode: String, CaseIterable, Identifiable {
        case days = "Days"
        case trends = "Trends"
        var id: String { rawValue }
    }

    @Environment(\.modelContext) private var modelContext
    /// Set by RootView from the time zone setting; drives what counts as a day.
    @Environment(\.calendar) private var calendar
    @Query(sort: \FeedEntry.startTime, order: .reverse) private var entries: [FeedEntry]
    @Query(sort: \WeightEntry.date, order: .reverse) private var weights: [WeightEntry]

    @AppStorage(FeedDefaults.volumeUnit) private var unitRaw = VolumeUnit.ounces.rawValue
    @AppStorage(AppSettings.feedingStyleKey) private var feedingStyleRaw = FeedingStyle.formula.rawValue
    @AppStorage(AppSettings.feedsPerDayKey) private var feedsPerDay = 0
    @AppStorage(BabyProfile.birthDateKey) private var birthInterval: Double = 0
    @AppStorage(AppSettings.currentBabyIDKey) private var currentBabyIDRaw = ""

    @State private var mode: Mode = .days
    @State private var editingEntry: FeedEntry?
    @State private var showSummary = false

    private var unit: VolumeUnit { VolumeUnit(rawValue: unitRaw) ?? .ounces }
    private var currentBabyID: UUID? { UUID(uuidString: currentBabyIDRaw) }
    private var activeEntries: [FeedEntry] { entries.active(for: currentBabyID) }
    private var groups: [DayGroup] { FeedStats.groupByDay(activeEntries, calendar: calendar) }

    private var targetML: Double? {
        let profile = BabyProfile(name: "", birthDate: birthInterval > 0 ? Date(timeIntervalSince1970: birthInterval) : nil)
        return FeedingGuidance.dailyTarget(
            weightGrams: weights.active(for: currentBabyID).first?.grams,
            ageDays: profile.ageInDays(),
            style: FeedingStyle(rawValue: feedingStyleRaw) ?? .formula,
            feedsPerDay: feedsPerDay
        )?.targetML
    }

    var body: some View {
        NavigationStack {
            Group {
                if activeEntries.isEmpty {
                    ContentUnavailableView(
                        "No feeds yet",
                        systemImage: "list.bullet.clipboard",
                        description: Text("Feeds you log will show up here, grouped by day.")
                    )
                } else {
                    List {
                        Section {
                            Picker("View", selection: $mode) {
                                ForEach(Mode.allCases) { mode in
                                    Text(mode.rawValue).tag(mode)
                                }
                            }
                            .pickerStyle(.segmented)
                            .listRowBackground(Color.clear)
                            .listRowInsets(EdgeInsets())
                        }

                        switch mode {
                        case .days:
                            daySections
                        case .trends:
                            Section {
                                TrendsView(groups: groups, unit: unit, targetML: targetML, calendar: calendar)
                                    .padding(.vertical, 8)
                            }
                        }
                    }
                    .listStyle(.insetGrouped)
                }
            }
            .navigationTitle("History")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        showSummary = true
                    } label: {
                        Label("Summary for the pediatrician", systemImage: "stethoscope")
                    }
                    .disabled(activeEntries.isEmpty)
                }
            }
            .sheet(item: $editingEntry) { entry in
                LogFeedSheet(mode: .edit(entry))
            }
            .sheet(isPresented: $showSummary) {
                SummarySheet()
            }
        }
    }

    private var daySections: some View {
        ForEach(groups) { group in
            Section {
                FeedTimelineStrip(entries: group.entries, day: group.day, calendar: calendar)
                    .padding(.vertical, 6)
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
                    Text(FeedStats.dayTitle(for: group.day, calendar: calendar))
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

    private func delete(_ toDelete: [FeedEntry]) {
        withAnimation {
            for entry in toDelete {
                entry.softDelete()
            }
        }
        FeedCoordinator.feedsDidChange(in: modelContext)
    }
}

#Preview {
    HistoryView()
        .modelContainer(for: [FeedEntry.self, WeightEntry.self, Baby.self], inMemory: true)
}
