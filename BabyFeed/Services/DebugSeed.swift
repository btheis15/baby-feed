#if DEBUG
import Foundation
import SwiftData

/// Fills the store with a realistic first fortnight — feeds, diapers,
/// weigh-ins and notes — so the charts, the pediatrician summary and the
/// guidance can be looked at with something that resembles real use.
///
/// No solid foods: the seeded baby is two weeks old, and the Foods section
/// doesn't open until four months.
///
/// Debug builds only, and only when launched with `--seed-demo-data`, so it
/// cannot run for anyone who isn't deliberately asking for it. It replaces
/// whatever is in the store, so it's reproducible.
@MainActor
enum DebugSeed {
    static let launchArgument = "--seed-demo-data"

    static var isRequested: Bool {
        CommandLine.arguments.contains(launchArgument)
    }

    /// A deterministic generator, so the same seed gives the same picture and
    /// a screenshot can be compared with the last one.
    private struct Rolling {
        private var state: UInt64
        init(_ seed: UInt64) { state = seed }
        mutating func next(_ upperBound: Int) -> Int {
            state = state &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
            return Int((state >> 33) % UInt64(max(1, upperBound)))
        }
    }

    static func run(in context: ModelContext) {
        let babyID = ((try? context.fetch(FetchDescriptor<Baby>())) ?? [])
            .first { $0.deletedAt == nil }?.uuid

        for feed in (try? context.fetch(FetchDescriptor<FeedEntry>())) ?? [] { context.delete(feed) }
        for weight in (try? context.fetch(FetchDescriptor<WeightEntry>())) ?? [] { context.delete(weight) }
        for note in (try? context.fetch(FetchDescriptor<CareNote>())) ?? [] { context.delete(note) }
        for diaper in (try? context.fetch(FetchDescriptor<DiaperEntry>())) ?? [] { context.delete(diaper) }
        for food in (try? context.fetch(FetchDescriptor<SolidFoodEntry>())) ?? [] { context.delete(food) }
        for concern in (try? context.fetch(FetchDescriptor<HealthConcern>())) ?? [] { context.delete(concern) }
        for medication in (try? context.fetch(FetchDescriptor<Medication>())) ?? [] { context.delete(medication) }
        for dose in (try? context.fetch(FetchDescriptor<MedicationDose>())) ?? [] { context.delete(dose) }
        for visit in (try? context.fetch(FetchDescriptor<DoctorVisit>())) ?? [] { context.delete(visit) }

        let calendar = AppSettings.calendar
        let today = calendar.startOfDay(for: .now)
        guard let birth = calendar.date(byAdding: .day, value: -14, to: today) else { return }

        // The profile is owned by the Baby model and mirrored down into
        // UserDefaults on every launch, so writing only the mirror gets
        // overwritten the next time the app starts. Sex belongs here too now
        // that it drives the growth percentiles – seeding only the mirror made
        // the percentile feature quietly disappear on the second launch.
        if let baby = BabyStore.currentBaby(in: context) {
            baby.name = "Nora"
            baby.birthDate = birth
            baby.sex = .female
            baby.dueDate = nil
            baby.markChanged()
        }

        let defaults = UserDefaults.standard
        defaults.set("Nora", forKey: BabyProfile.nameKey)
        defaults.set(birth.timeIntervalSince1970, forKey: BabyProfile.birthDateKey)
        defaults.set(BabySex.female.rawValue, forKey: BabyProfile.sexKey)
        defaults.set(0, forKey: BabyProfile.dueDateKey)
        defaults.set(VolumeUnit.ounces.rawValue, forKey: FeedDefaults.volumeUnit)
        defaults.set("Brian", forKey: AppSettings.displayNameKey)
        // Let the guidance and the interval drive themselves.
        defaults.set(0, forKey: AppSettings.feedsPerDayKey)
        defaults.set(0, forKey: AppSettings.intervalMinutesKey)
        FeedDefaults.setDefaultAmountML(nil, for: .formula)
        FeedDefaults.setDefaultAmountML(nil, for: .breastMilk)

        var random = Rolling(20_260_917)
        var feedCount = 0

        for dayOffset in 0...14 {
            guard let day = calendar.date(byAdding: .day, value: dayOffset - 14, to: today) else { continue }
            // Nine feeds a day in week one, easing to seven by two weeks.
            let feedsToday = dayOffset < 7 ? 9 : (dayOffset < 12 ? 8 : 7)
            // Volume ramps from roughly 40 ml to roughly 100 ml over the fortnight.
            let baseML = 40.0 + Double(dayOffset) * 4.0

            for index in 0..<feedsToday {
                let spacing = 24.0 / Double(feedsToday)
                let minutesIn = Int((Double(index) * spacing) * 60) + random.next(45)
                guard let start = calendar.date(byAdding: .minute, value: minutesIn, to: day),
                      start <= .now else { continue }

                if index % 6 == 5 {
                    context.insert(FeedEntry(
                        babyID: babyID,
                        startTime: start,
                        kind: .nursing,
                        durationMinutes: 12 + random.next(10),
                        side: [NursingSide.left, .right, .both][random.next(3)],
                        loggedByName: "Brian"
                    ))
                } else {
                    // Deliberate spread, including feeds well under the
                    // recommendation, because that's what real logs look like.
                    let jitter = Double(random.next(46)) - 20
                    let amount = max(20, ((baseML + jitter) / 10).rounded() * 10)
                    context.insert(FeedEntry(
                        babyID: babyID,
                        startTime: start,
                        kind: index.isMultiple(of: 2) ? .formula : .breastMilk,
                        amountML: amount,
                        note: (dayOffset == 9 && index == 3) ? "spit up a little" : "",
                        loggedByName: index.isMultiple(of: 3) ? "Brian" : "Sam"
                    ))
                }
                feedCount += 1
            }
        }

        // Diapers the way the first fortnight goes: one or two on the first
        // day, climbing as the milk comes in, then six to eight wet and three
        // or four dirty a day from day five — the counts IntakeGuidance tells
        // parents to expect. Generated after the feeds, so the feeds come out
        // the same as they always have.
        var diaperCount = 0
        for dayOffset in 0...14 {
            guard let day = calendar.date(byAdding: .day, value: dayOffset - 14, to: today) else { continue }
            let wet = dayOffset < 5 ? dayOffset + 1 : 6 + random.next(3)
            let dirty = dayOffset < 5 ? min(dayOffset + 1, 3) : 3 + random.next(2)
            // Some changes are both at once: one row, counted once toward each tally.
            let both = min(wet, dirty) / 2
            var kinds = Array(repeating: DiaperKind.both, count: both)
                + Array(repeating: DiaperKind.wet, count: wet - both)
                + Array(repeating: DiaperKind.dirty, count: dirty - both)
            for index in stride(from: kinds.count - 1, to: 0, by: -1) {
                kinds.swapAt(index, random.next(index + 1))
            }

            let spacing = 24.0 / Double(kinds.count)
            for (index, kind) in kinds.enumerated() {
                let minutesIn = Int(Double(index) * spacing * 60) + random.next(40)
                guard let time = calendar.date(byAdding: .minute, value: minutesIn, to: day),
                      time <= .now else { continue }
                context.insert(DiaperEntry(
                    babyID: babyID,
                    time: time,
                    kind: kind,
                    loggedByName: index.isMultiple(of: 2) ? "Sam" : "Brian"
                ))
                diaperCount += 1
            }
        }

        // Birth weight, the normal day-three dip, back to birth weight by day
        // eleven, then climbing.
        let weighIns: [(day: Int, grams: Double, note: String)] = [
            (0, 3260, "birth weight"),
            (3, 3040, "day 3 check"),
            (11, 3300, "pediatrician visit"),
            (14, 3420, ""),
        ]
        for weighIn in weighIns {
            guard let date = calendar.date(byAdding: .day, value: weighIn.day - 14, to: today) else { continue }
            context.insert(WeightEntry(
                babyID: babyID,
                date: date,
                grams: weighIn.grams,
                note: weighIn.note,
                loggedByName: "Brian"
            ))
        }

        // The point of the notes log: things you'd never remember two weeks
        // later at the appointment. Logged by whoever was free at the time.
        let notes: [(day: Int, hour: Int, kind: CareNoteKind, text: String, severity: CareNoteSeverity?, author: String)] = [
            (3, 22, .breathing, "Snuffly, noisy breathing while asleep. Settled once we raised the mattress.", .mild, "Brian"),
            (6, 19, .crying, "Inconsolable for about 90 minutes in the evening. Nothing helped.", .moderate, "Sam"),
            (9, 14, .spitUp, "Brought up most of a bottle. Fine straight afterwards.", nil, "Brian"),
            (11, 9, .rash, "Small red patch on the left cheek, not spreading.", .mild, "Sam"),
            (13, 3, .sleep, "Slept a five-hour stretch for the first time.", nil, "Brian"),
        ]
        for note in notes {
            guard let day = calendar.date(byAdding: .day, value: note.day - 14, to: today),
                  let date = calendar.date(byAdding: .hour, value: note.hour, to: day),
                  date <= .now
            else { continue }
            context.insert(CareNote(
                babyID: babyID,
                date: date,
                kind: note.kind,
                note: note.text,
                severity: note.severity,
                loggedByName: note.author
            ))
        }

        seedHealth(babyID: babyID, birth: birth, today: today, calendar: calendar, in: context)

        try? context.save()
        print("[DebugSeed] \(feedCount) feeds and \(diaperCount) diapers over 15 days, \(weighIns.count) weigh-ins, \(notes.count) notes, born \(birth)")
    }

    /// A red eye that's still going on (with an update), a stuffy nose that
    /// cleared, vitamin D most mornings but not yet today, two gas drops
    /// yesterday, and the first-week and weight-check visits.
    private static func seedHealth(babyID: UUID?, birth: Date, today: Date, calendar: Calendar, in context: ModelContext) {
        func at(daysAgo: Int, hour: Int, minute: Int = 0) -> Date {
            let day = calendar.date(byAdding: .day, value: -daysAgo, to: today) ?? today
            return calendar.date(bySettingHour: hour, minute: minute, second: 0, of: day) ?? day
        }

        let eye = HealthConcern(babyID: babyID, title: "Red left eye", kind: .eye, startedAt: at(daysAgo: 3, hour: 7),
                                severity: .mild, note: "Goopy in the mornings, wiped clean with cooled boiled water.",
                                loggedByName: "Sam")
        context.insert(eye)
        let update = CareNote(babyID: babyID, date: at(daysAgo: 1, hour: 8), kind: .eye,
                              note: "Less red today, still a bit goopy on waking.", loggedByName: "Brian")
        update.concernID = eye.uuid
        context.insert(update)

        let nose = HealthConcern(babyID: babyID, title: "Stuffy nose", kind: .cough, startedAt: at(daysAgo: 12, hour: 20),
                                 severity: .mild, loggedByName: "Brian")
        nose.resolvedAt = at(daysAgo: 7, hour: 9)
        nose.outcome = "Cleared with saline drops and suction."
        context.insert(nose)

        let vitaminD = Medication(babyID: babyID, name: "Vitamin D", kind: .supplement, doseUnit: .drop,
                                  schedule: .daily, timesPerDay: 1, maxDosesPer24h: 1,
                                  startDate: at(daysAgo: 12, hour: 0), loggedByName: "Brian")
        context.insert(vitaminD)
        for daysAgo in 1...10 {
            context.insert(MedicationDose(babyID: babyID, medicationID: vitaminD.uuid, medicationName: "Vitamin D",
                                          time: at(daysAgo: daysAgo, hour: 8, minute: 10), amount: 1, unit: .drop,
                                          loggedByName: daysAgo.isMultiple(of: 3) ? "Sam" : "Brian"))
        }

        let gasDrops = Medication(babyID: babyID, name: "Gas drops", kind: .medicine, doseUnit: .ml,
                                  schedule: .asNeeded, minHoursBetween: 2, startDate: at(daysAgo: 6, hour: 0),
                                  loggedByName: "Sam")
        context.insert(gasDrops)
        for (hour, author) in [(2, "Sam"), (19, "Brian")] {
            context.insert(MedicationDose(babyID: babyID, medicationID: gasDrops.uuid, medicationName: "Gas drops",
                                          time: at(daysAgo: 1, hour: hour, minute: 30), amount: 0.3, unit: .ml,
                                          loggedByName: author))
        }

        let firstWeek = DoctorVisit(babyID: babyID, date: at(daysAgo: 10, hour: 10), kind: .checkup, provider: "Dr. Patel",
                                    reason: "First-week visit", doctorNotes: "Feeding well, jaundice fading.",
                                    loggedByName: "Brian")
        context.insert(firstWeek)
        let weightCheck = DoctorVisit(babyID: babyID, date: at(daysAgo: 3, hour: 11), kind: .followUp,
                                      provider: "Dr. Patel", reason: "Weight check",
                                      doctorNotes: "Back to birth weight. Keep feeding on demand.", loggedByName: "Sam")
        weightCheck.followUpNote = "2-month shots"
        weightCheck.followUpDate = calendar.date(byAdding: .month, value: 2, to: birth)
        context.insert(weightCheck)
    }
}

/// Where to open, for screenshots taken from the command line:
/// `--open-tab timeline|charts|health|baby|settings`, `--open-sheet add|share`,
/// `--debug-nursing <minutes ago>` and `--debug-open-url <babyfeed://…>`.
/// Debug builds only, like the seed.
@MainActor
enum DebugLaunch {
    static func apply(to router: AppRouter) {
        let arguments = CommandLine.arguments
        func value(after flag: String) -> String? {
            guard let index = arguments.firstIndex(of: flag), arguments.indices.contains(index + 1) else { return nil }
            return arguments[index + 1]
        }
        switch value(after: "--open-tab") {
        case "timeline": router.tab = .timeline
        case "charts":
            router.tab = .timeline
            router.timelineShowsCharts = true
        case "health": router.tab = .health
        case "baby": router.tab = .baby
        case "settings": router.tab = .settings
        default: break
        }
        switch value(after: "--open-sheet") {
        case "add": router.sheet = .addEntry
        case "share": if let id = AppSettings.currentBabyID { router.sheet = .share(id) }
        default: break
        }
        // A nursing timer already running, for the hero and Live Activity.
        if let minutes = value(after: "--debug-nursing").flatMap(Double.init) {
            NursingTimer.shared.start(side: .left, at: Date.now.addingTimeInterval(-minutes * 60))
        }
        // The same path a tapped link or a scanned QR takes, minus the
        // simulator's "Open in Baby Feed?" prompt.
        if let link = value(after: "--debug-open-url"), let url = URL(string: link) {
            router.handle(url: url)
        }
        runSyncChecks(restorePhrase: value(after: "--debug-restore"))
    }

    /// Sharing, end to end, without tapping: `--debug-connect` backs up the
    /// current baby, `--debug-invite` logs a join link for it (open it on a
    /// second simulator with `--debug-open-url`), `--debug-restore <phrase>`
    /// restores, `--debug-name <name>` and `--debug-log-diaper` log something
    /// to sync. Results go to the log: `simctl spawn <device> log show`.
    private static func runSyncChecks(restorePhrase: String?) {
        let arguments = CommandLine.arguments
        let context = AppModelContainer.shared.mainContext
        let engine = SyncEngine.shared
        Task { @MainActor in
            do {
                if let restorePhrase {
                    try await engine.recover(key: restorePhrase)
                    NSLog("%@", "[DebugLaunch] restored: babies \(BabyStore.allBabies(in: context).map(\.displayName)), status \(engine.status)")
                }
                if arguments.contains("--debug-connect") {
                    try await engine.ensureConnected(.backUp)
                    NSLog("%@", "[DebugLaunch] connected: status \(engine.status), phrase \(engine.recoveryPhrase ?? "none"), pending \(engine.pendingCount(in: context))")
                }
                if let index = arguments.firstIndex(of: "--debug-name"), arguments.indices.contains(index + 1) {
                    await engine.updateDisplayName(arguments[index + 1])
                }
                if arguments.contains("--debug-log-diaper"), let baby = BabyStore.currentBaby(in: context) {
                    context.insert(DiaperEntry(babyID: baby.uuid, kind: .both, loggedByName: AppSettings.displayName))
                    FeedCoordinator.feedsDidChange(in: context, triggerSync: false)
                    await engine.syncNow()
                    NSLog("%@", "[DebugLaunch] logged a diaper: status \(engine.status), pending \(engine.pendingCount(in: context))")
                }
                if arguments.contains("--debug-invite"), let baby = BabyStore.currentBaby(in: context) {
                    let invite = try await engine.invite(for: baby)
                    if let server = SyncCredentials.serverURL, let link = SyncLink.url(code: invite.code, server: server) {
                        NSLog("%@", "[DebugLaunch] invite: \(link.absoluteString)")
                    }
                }
            } catch {
                NSLog("%@", "[DebugLaunch] failed: \(error)")
            }
        }
    }
}
#endif
