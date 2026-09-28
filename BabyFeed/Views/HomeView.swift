import SwiftData
import SwiftUI

/// The main screen: a countdown to the next feed, the feed and diaper
/// buttons, one "+" for everything else, the last 24 hours and the last few
/// things logged. Anything logged less often waits one tap further in.
struct HomeView: View {
    @Environment(\.calendar) private var calendar
    @Environment(\.timeZone) private var timeZone
    @Environment(\.scenePhase) private var scenePhase
    @Environment(AppRouter.self) private var router
    @Environment(\.modelContext) private var modelContext
    @Environment(ToastCenter.self) private var toasts
    @Query(sort: \FeedEntry.startTime, order: .reverse) private var entries: [FeedEntry]
    @Query(sort: \WeightEntry.date, order: .reverse) private var weights: [WeightEntry]
    @Query(sort: \DiaperEntry.time, order: .reverse) private var diapers: [DiaperEntry]

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

    /// The time the 24-hour numbers are worked out at. They drift slowly as
    /// feeds age out of the window, so this moves every ten minutes and
    /// whenever the app comes to the front — not every few seconds. Only the
    /// countdown ticks, once a minute, in its own TimelineView.
    ///
    /// A plain value rather than an outer TimelineView on purpose: a
    /// TimelineView nested inside another one, in a List, sends SwiftUI into
    /// a redraw loop that pins the main thread at 100% before the first frame.
    @State private var clock = Date.now
    @State private var nursing = NursingTimer.shared
    /// Done on a timer left running over an hour: save as is, or fix the time.
    @State private var confirmLongNursing = false

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
                // Reading the clock is what re-runs this every ten minutes;
                // the numbers themselves are worked out at the real time, so a
                // feed logged a moment ago is already in them.
                let now = max(clock, .now)
                let visible = entries.active(for: currentBabyID)
                let babyWeights = weights.active(for: currentBabyID)
                let latestWeight = babyWeights.first
                let recent = FeedStats.entries(visible, within: 24 * 60 * 60, now: now)
                let summary = FeedSummary(recent)
                let babyDiapers = diapers.active(for: currentBabyID)
                let diaperTally = DiaperTally(babyDiapers.within(24 * 60 * 60, now: now))
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
                let ageDays = profile.ageInDays(on: now, calendar: calendar)
                let birthWeight = BirthWeightStatus(weights: babyWeights, birthDate: profile.birthDate, calendar: calendar)

                List {
                    Section {
                        // Once a minute. Anchored to a running nursing timer's
                        // start, so its minutes turn over when a real minute
                        // of nursing has passed rather than on the clock's.
                        TimelineView(.periodic(from: nursing.session?.startedAt ?? Self.minuteAnchor, by: 60)) { minute in
                            if let session = nursing.session {
                                NursingHero(
                                    session: session,
                                    now: minute.date,
                                    timeZone: timeZone,
                                    onSwitch: { nursing.switchSide() },
                                    onDone: { finishNursing(now: minute.date) },
                                    onCancel: { nursing.cancel() }
                                )
                            } else {
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
                                    showsNewbornWakeLine: showsNewbornWakeLine(lastFeed: visible.first, birthWeight: birthWeight,
                                                                               now: minute.date),
                                    onLog: { router.openLog(kind: visible.first?.kind) }
                                )
                            }
                        }
                    }

                    Section {
                        QuickLogButtons(unit: unit, nursingSide: NextSide.suggestion(after: visible)) { kind in
                            router.openLog(kind: kind)
                        }
                        .listRowBackground(Color.clear)
                        .listRowInsets(EdgeInsets())
                    }

                    Section("Diapers") {
                        DiaperSection(last: babyDiapers.first, tally: diaperTally)
                            .listRowBackground(Color.clear)
                            .listRowInsets(EdgeInsets())
                    }

                    if let ageDays, EnoughSummary.shows(ageDays: ageDays) {
                        let enough = EnoughSummary(diapers: babyDiapers, feeds: visible, ageDays: ageDays, now: now)
                        Section {
                            NavigationLink {
                                IntakeView(
                                    babyName: profile.displayName,
                                    ageDays: ageDays,
                                    consumedML: summary.totalML,
                                    targetML: target?.targetML,
                                    unit: unit,
                                    logged: enough
                                )
                            } label: {
                                GettingEnoughCard(summary: enough, birthWeight: birthWeight, ageDays: ageDays,
                                                  weightUnit: weightUnit, now: now)
                            }
                        }
                    }

                    RightNowCard(babyID: currentBabyID, birthDate: profile.birthDate)

                    SyncSetupCard(babyName: profile.displayName,
                                  hasRealBaby: !babyName.isEmpty || !visible.isEmpty)

                    Section {
                        Button {
                            router.sheet = .addEntry
                        } label: {
                            Label {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("Log something else")
                                        .font(.headline)
                                    Text(addEntrySubtitle(now: now))
                                        .font(.subheadline)
                                        // Grey, not the button's tint faded.
                                        .foregroundStyle(Color.secondary)
                                }
                            } icon: {
                                Image(systemName: "plus.circle.fill")
                                    .font(.title2)
                            }
                            .padding(.vertical, 2)
                        }
                    }

                    Section {
                        NavigationLink {
                            Last24HoursView(
                                summary: summary,
                                diapers: diaperTally,
                                target: target,
                                projection: projection,
                                unit: unit,
                                weightText: latestWeight.map { weightUnit.format(grams: $0.grams) },
                                weightUnit: weightUnit,
                                babyName: profile.displayName
                            )
                        } label: {
                            Last24HoursCard(summary: summary, diapers: diaperTally, target: target, unit: unit)
                        }
                    }

                    RecentSection(babyID: currentBabyID, unit: unit, weightUnit: weightUnit)
                }
                .listStyle(.insetGrouped)
            }
            .navigationTitle(babyName.isEmpty ? "Baby Feed" : babyName)
            .toolbar {
                if SyncEngine.shared.hasServer, let babyID = currentBabyID {
                    ToolbarItem(placement: .primaryAction) {
                        Button {
                            router.sheet = .share(babyID)
                        } label: {
                            Label("Share \(profile.displayName)'s log", systemImage: "person.badge.plus")
                        }
                    }
                }
            }
            .confirmationDialog("That's a long feed", isPresented: $confirmLongNursing, titleVisibility: .visible) {
                if let session = nursing.session {
                    Button("Save \(session.minutes(at: .now)) min") { saveNursing(fixTime: false) }
                    Button("Save and fix the time") { saveNursing(fixTime: true) }
                }
                Button("Keep going", role: .cancel) {}
            } message: {
                Text("The timer has been running for over an hour. If it was left on, fix the time after saving.")
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
    /// weight. With a birth weight logged, that's until the weigh-ins say so
    /// (up to four weeks); without one, the first two weeks, when most are.
    private func showsNewbornWakeLine(lastFeed: FeedEntry?, birthWeight: BirthWeightStatus, now: Date) -> Bool {
        guard let lastFeed, let ageDays = profile.ageInDays(on: now, calendar: calendar) else { return false }
        let stillApplies = birthWeight.hasBirthWeight
            ? !birthWeight.isRegained && ageDays < 28
            : ageDays < 14
        guard stillApplies else { return false }
        return now.timeIntervalSince(lastFeed.startTime) >= FeedingGuidance.newbornMaxGapHours * 3600
    }

    // MARK: Nursing timer

    /// Any whole minute: the countdown ticks on the clock's minutes.
    private static let minuteAnchor = Date(timeIntervalSinceReferenceDate: 0)

    private func finishNursing(now: Date) {
        guard let session = nursing.session else { return }
        if session.isProbablyForgotten(at: now) {
            confirmLongNursing = true
        } else {
            saveNursing(fixTime: false)
        }
    }

    private func saveNursing(fixTime: Bool) {
        guard let feed = nursing.finish(in: modelContext) else { return }
        if fixTime {
            router.sheet = .editEntry(.feed(feed.persistentModelID))
        } else {
            toasts.logged(.feed(feed), detail: feed.detailText(unit: unit), context: modelContext, router: router)
        }
    }

    /// What's behind the "+", so nobody has to open it to find out.
    private func addEntrySubtitle(now: Date) -> String {
        let months = profile.ageInDays(on: now, calendar: calendar).map(FoodGuidance.months(fromDays:))
        let offersFood = months.map { !FoodTexture.available(atMonths: $0).isEmpty } ?? false
        return offersFood ? "Medicine, a note, a concern, a visit, weight or food"
                          : "Medicine, a note, a concern, a visit or weight"
    }
}

#Preview {
    HomeView()
        .environment(AppRouter())
        .environment(ToastCenter())
        .modelContainer(.preview)
}
