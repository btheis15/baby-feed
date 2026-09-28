import SwiftData
import SwiftUI

/// The main screen: a countdown to the next feed, the big log buttons,
/// diapers, the daily target, 24-hour totals and the recent feeds.
struct HomeView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.calendar) private var calendar
    @Environment(\.timeZone) private var timeZone
    @Environment(\.scenePhase) private var scenePhase
    @Environment(AppRouter.self) private var router
    @Query(sort: \FeedEntry.startTime, order: .reverse) private var entries: [FeedEntry]
    @Query(sort: \WeightEntry.date, order: .reverse) private var weights: [WeightEntry]

    @AppStorage(FeedDefaults.volumeUnit) private var unitRaw = VolumeUnit.ounces.rawValue
    @AppStorage(AppSettings.weightUnitKey) private var weightUnitRaw = WeightUnit.poundsOunces.rawValue
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
    /// The time the 24-hour numbers are worked out at. They drift slowly as
    /// feeds age out of the window, so this moves every ten minutes and
    /// whenever the app comes to the front — not every few seconds. Only the
    /// countdown ticks, once a minute, in its own TimelineView.
    ///
    /// A plain value rather than an outer TimelineView on purpose: a
    /// TimelineView nested inside another one, in a List, sends SwiftUI into
    /// a redraw loop that pins the main thread at 100% before the first frame.
    @State private var clock = Date.now

    private var unit: VolumeUnit { VolumeUnit(rawValue: unitRaw) ?? .ounces }
    private var weightUnit: WeightUnit { WeightUnit(rawValue: weightUnitRaw) ?? .poundsOunces }
    private var feedingStyle: FeedingStyle { FeedingStyle(rawValue: feedingStyleRaw) ?? .formula }
    private var currentBabyID: UUID? { UUID(uuidString: currentBabyIDRaw) }
    private var profile: BabyProfile {
        BabyProfile(
            name: babyName,
            birthDate: birthInterval > 0 ? Date(timeIntervalSince1970: birthInterval) : nil,
            sex: BabySex(rawValue: sexRaw) ?? .unspecified,
            dueDate: dueInterval > 0 ? Date(timeIntervalSince1970: dueInterval) : nil
        )
    }

    var body: some View {
        NavigationStack {
            Group {
                let now = clock
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

                List {
                    Section {
                        TimelineView(.everyMinute) { minute in
                            NextFeedCard(
                                lastFeed: visible.first,
                                countdown: AppSettings.countdown(
                                    lastFeed: visible.first?.startTime,
                                    intervalRaw: intervalMinutesRaw,
                                    now: minute.date
                                ),
                                unit: unit,
                                now: minute.date,
                                timeZone: timeZone,
                                showsNewbornWakeLine: showsNewbornWakeLine(lastFeed: visible.first, now: minute.date),
                                onLog: { router.openLog(kind: visible.first?.kind) }
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

                    Section("Diapers") {
                        DiaperSection()
                            .listRowBackground(Color.clear)
                            .listRowInsets(EdgeInsets())
                    }

                    // Only once the AAP stages open anything beyond milk —
                    // before four months (or without a birthday) there is
                    // nothing to log, so there is nothing to show.
                    if let ageMonths = profile.ageInDays(on: now, calendar: calendar).map(FoodGuidance.months(fromDays:)),
                       !FoodTexture.available(atMonths: ageMonths).isEmpty {
                        Section("Foods") {
                            FoodLogSection(ageMonths: ageMonths)
                                .listRowBackground(Color.clear)
                                .listRowInsets(EdgeInsets())
                        }
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
            }
            .navigationTitle(babyName.isEmpty ? "Baby Feed" : babyName)
            .sheet(item: $newFeedKind) { kind in
                LogFeedSheet(mode: .new(kind))
            }
            .sheet(item: $editingEntry) { entry in
                LogFeedSheet(mode: .edit(entry))
            }
            .onChange(of: scenePhase) { _, phase in
                if phase == .active { clock = .now }
            }
            .task {
                clock = .now
                while !Task.isCancelled {
                    try? await Task.sleep(for: .seconds(600))
                    clock = .now
                }
            }
        }
    }

    /// The AAP's guidance for the first weeks: a newborn who has gone about
    /// four hours without a feed is woken for one, until they're back to birth
    /// weight. Two weeks is when most babies are; Phase 4 of the roadmap swaps
    /// this for the actual weigh-ins once birth weight is tracked.
    private func showsNewbornWakeLine(lastFeed: FeedEntry?, now: Date) -> Bool {
        guard let lastFeed,
              let ageDays = profile.ageInDays(on: now, calendar: calendar),
              ageDays < 14
        else { return false }
        return now.timeIntervalSince(lastFeed.startTime) >= FeedingGuidance.newbornMaxGapHours * 3600
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
        .modelContainer(.preview)
}
