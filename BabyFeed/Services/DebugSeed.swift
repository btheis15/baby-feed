#if DEBUG
import Foundation
import SwiftData

/// Fills the store with a realistic fortnight of feeds and weigh-ins, so the
/// trends, the pediatrician summary and the guidance can be looked at with
/// something that resembles real use.
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

        let calendar = AppSettings.calendar
        let today = calendar.startOfDay(for: .now)
        guard let birth = calendar.date(byAdding: .day, value: -14, to: today) else { return }

        // Name and birthday are owned by the Baby model and mirrored down into
        // UserDefaults on every launch, so writing only the mirror gets
        // overwritten the next time the app starts. Sex and the due date live
        // in UserDefaults alone, which is why they survive on their own.
        if let baby = BabyStore.currentBaby(in: context) {
            baby.name = "Nora"
            baby.birthDate = birth
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

        try? context.save()
        print("[DebugSeed] \(feedCount) feeds over 15 days, \(weighIns.count) weigh-ins, born \(birth)")
    }
}
#endif
