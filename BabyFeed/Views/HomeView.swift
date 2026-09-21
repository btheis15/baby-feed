import SwiftData
import SwiftUI

/// The main screen: time since last feed, daily target, 24-hour totals,
/// big log buttons, and the recent feeds.
struct HomeView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.calendar) private var calendar
    @Environment(AppRouter.self) private var router
    @Query(sort: \FeedEntry.startTime, order: .reverse) private var entries: [FeedEntry]
    @Query(sort: \WeightEntry.date, order: .reverse) private var weights: [WeightEntry]

    @AppStorage(FeedDefaults.volumeUnit) private var unitRaw = VolumeUnit.ounces.rawValue
    @AppStorage(AppSettings.weightUnitKey) private var weightUnitRaw = WeightUnit.poundsOunces.rawValue
    @AppStorage(AppSettings.remindersEnabledKey) private var remindersEnabled = false
    /// 0 means "follow what's typical for this age"; resolved below.
    @AppStorage(AppSettings.intervalMinutesKey) private var intervalMinutesRaw = 0
    @AppStorage(AppSettings.feedingStyleKey) private var feedingStyleRaw = FeedingStyle.formula.rawValue
    @AppStorage(AppSettings.feedsPerDayKey) private var feedsPerDay = 0
    @AppStorage(BabyProfile.nameKey) private var babyName = ""
    @AppStorage(BabyProfile.birthDateKey) private var birthInterval: Double = 0
    @AppStorage(BabyProfile.sexKey) private var sexRaw = BabySex.unspecified.rawValue
    @AppStorage(BabyProfile.dueDateKey) private var dueInterval: Double = 0
    @AppStorage(AppSettings.currentBabyIDKey) private var currentBabyIDRaw = ""

    @State private var newFeedKind: FeedKind?
    @State private var editingEntry: FeedEntry?

    private var unit: VolumeUnit { VolumeUnit(rawValue: unitRaw) ?? .ounces }
    private var weightUnit: WeightUnit { WeightUnit(rawValue: weightUnitRaw) ?? .poundsOunces }
    private var feedingStyle: FeedingStyle { FeedingStyle(rawValue: feedingStyleRaw) ?? .formula }
    private var currentBabyID: UUID? { UUID(uuidString: currentBabyIDRaw) }
    private var intervalMinutes: Int { AppSettings.resolvedIntervalMinutes(raw: intervalMinutesRaw) }
    private var profile: BabyProfile {
        BabyProfile(name: babyName, birthInterval: birthInterval, sexRaw: sexRaw, dueInterval: dueInterval)
    }

    var body: some View {
        NavigationStack {
            // Everything here is recomputed when the log, the settings or the
            // baby change — not on a timer. Only the hero counter ticks.
            let now = Date.now
            let visible = entries.active(for: currentBabyID)
            let babyWeights = weights.active(for: currentBabyID)
            let latestWeight = babyWeights.first
            let recent = FeedStats.entries(visible, within: 24 * 60 * 60, now: now)
            let summary = FeedSummary(recent)
            // Once the sex is known the target follows the baby's percentile
            // forward instead of sitting frozen at the last weigh-in.
            let guidance = FeedingGuidance.currentTarget(
                weights: babyWeights,
                profile: profile,
                style: feedingStyle,
                feedsPerDay: feedsPerDay,
                now: now,
                calendar: calendar
            )
            let target = guidance.target
            let projection = guidance.projection
            let dueDate = visible.first.map { $0.startTime.addingTimeInterval(Double(intervalMinutes) * 60) }

            List {
                Section {
                    // The one thing on this screen that has to keep moving by
                    // itself. Wrapping the whole List in this — which is what
                    // it used to do — re-ran the WHO percentile projection and
                    // regrouped the log every 30 seconds to advance a minute
                    // counter.
                    TimelineView(.periodic(from: .now, by: 30)) { context in
                        LastFedCard(
                            lastFeed: visible.first,
                            unit: unit,
                            now: context.date,
                            nudgeAfter: remindersEnabled ? Double(intervalMinutes) * 60 : 3 * 60 * 60,
                            dueDate: remindersEnabled ? dueDate : nil
                        )
                    }
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
                        weightText: latestWeight.map { weightUnit.format(grams: $0.grams) },
                        babyName: profile.displayName,
                        projection: projection,
                        weightUnit: weightUnit
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
                entry.softDelete()
            }
        }
        FeedCoordinator.feedsDidChange(in: modelContext)
    }
}

#Preview {
    HomeView()
        .environment(AppRouter())
        .modelContainer(for: [FeedEntry.self, WeightEntry.self, Baby.self], inMemory: true)
}
