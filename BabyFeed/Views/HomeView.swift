import SwiftData
import SwiftUI

/// The main screen: time since last feed, daily target, 24-hour totals,
/// big log buttons, and the recent feeds.
struct HomeView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(AppRouter.self) private var router
    @Query(sort: \FeedEntry.startTime, order: .reverse) private var entries: [FeedEntry]
    @Query(sort: \WeightEntry.date, order: .reverse) private var weights: [WeightEntry]

    @AppStorage(FeedDefaults.volumeUnit) private var unitRaw = VolumeUnit.ounces.rawValue
    @AppStorage(AppSettings.weightUnitKey) private var weightUnitRaw = WeightUnit.poundsOunces.rawValue
    @AppStorage(AppSettings.remindersEnabledKey) private var remindersEnabled = false
    @AppStorage(AppSettings.intervalMinutesKey) private var intervalMinutes = AppSettings.defaultIntervalMinutes
    @AppStorage(AppSettings.feedingStyleKey) private var feedingStyleRaw = FeedingStyle.formula.rawValue
    @AppStorage(AppSettings.feedsPerDayKey) private var feedsPerDay = 0
    @AppStorage(BabyProfile.nameKey) private var babyName = ""
    @AppStorage(BabyProfile.birthDateKey) private var birthInterval: Double = 0

    @State private var newFeedKind: FeedKind?
    @State private var editingEntry: FeedEntry?

    private var unit: VolumeUnit { VolumeUnit(rawValue: unitRaw) ?? .ounces }
    private var weightUnit: WeightUnit { WeightUnit(rawValue: weightUnitRaw) ?? .poundsOunces }
    private var feedingStyle: FeedingStyle { FeedingStyle(rawValue: feedingStyleRaw) ?? .formula }
    private var profile: BabyProfile {
        BabyProfile(name: babyName, birthDate: birthInterval > 0 ? Date(timeIntervalSince1970: birthInterval) : nil)
    }

    var body: some View {
        NavigationStack {
            // Re-renders every 30 seconds so the counter stays live.
            TimelineView(.periodic(from: .now, by: 30)) { context in
                let now = context.date
                let recent = FeedStats.entries(entries, within: 24 * 60 * 60, now: now)
                let summary = FeedSummary(recent)
                let target = FeedingGuidance.dailyTarget(
                    weightGrams: weights.first?.grams,
                    ageDays: profile.ageInDays(on: now),
                    style: feedingStyle,
                    feedsPerDay: feedsPerDay
                )
                let dueDate = entries.first.map { $0.startTime.addingTimeInterval(Double(intervalMinutes) * 60) }

                List {
                    Section {
                        LastFedCard(
                            lastFeed: entries.first,
                            unit: unit,
                            now: now,
                            nudgeAfter: remindersEnabled ? Double(intervalMinutes) * 60 : 3 * 60 * 60,
                            dueDate: remindersEnabled ? dueDate : nil
                        )
                    }

                    Section {
                        QuickLogButtons(unit: unit) { kind in
                            newFeedKind = kind
                        }
                        .listRowBackground(Color.clear)
                        .listRowInsets(EdgeInsets())
                    }

                    Section {
                        GuidanceCard(
                            target: target,
                            consumedML: summary.totalML,
                            nursingMinutes: summary.nursingMinutes,
                            unit: unit,
                            weightText: weights.first.map { weightUnit.format(grams: $0.grams) },
                            babyName: profile.displayName
                        ) {
                            router.tab = .baby
                        }
                    }

                    Section {
                        SummaryCard(title: "Last 24 hours", summary: summary, unit: unit)
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
            .navigationTitle(babyName.isEmpty ? "Baby Feed" : babyName)
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
        FeedCoordinator.feedsDidChange(in: modelContext)
    }
}

#Preview {
    HomeView()
        .environment(AppRouter())
        .modelContainer(for: [FeedEntry.self, WeightEntry.self], inMemory: true)
}
