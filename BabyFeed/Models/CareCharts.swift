import Foundation

/// How far back the charts look.
enum ChartRange: String, CaseIterable, Identifiable {
    case twoWeeks, month, threeMonths, sinceLastVisit

    var id: String { rawValue }

    var title: String {
        switch self {
        case .twoWeeks: "2 weeks"
        case .month: "1 month"
        case .threeMonths: "3 months"
        case .sinceLastVisit: "Since the last visit"
        }
    }

    /// "the last 2 weeks", for the sentence above a chart.
    var phrase: String {
        switch self {
        case .twoWeeks: "the last 2 weeks"
        case .month: "the last month"
        case .threeMonths: "the last 3 months"
        case .sinceLastVisit: "since the last visit"
        }
    }

    /// "over the last 2 weeks", or "since the last visit": the phrase with its
    /// preposition, so a sentence never reads "over since the last visit".
    var overPhrase: String {
        self == .sinceLastVisit ? phrase : "over \(phrase)"
    }

    /// From the start of the first day to the end of today. Since the last
    /// visit falls back to two weeks when there hasn't been one, and nothing
    /// starts before the day the baby was born: three months of axis for a
    /// three-week-old is mostly empty space.
    func interval(now: Date, lastVisit: Date?, birthDate: Date? = nil, calendar: Calendar) -> DateInterval {
        let today = calendar.startOfDay(for: now)
        let end = calendar.date(byAdding: .day, value: 1, to: today) ?? now
        var start: Date
        switch self {
        case .twoWeeks: start = calendar.date(byAdding: .day, value: -13, to: today) ?? today
        case .month: start = calendar.date(byAdding: .day, value: -29, to: today) ?? today
        case .threeMonths: start = calendar.date(byAdding: .day, value: -89, to: today) ?? today
        case .sinceLastVisit:
            start = lastVisit.map { calendar.startOfDay(for: $0) }
                ?? calendar.date(byAdding: .day, value: -13, to: today) ?? today
        }
        if let birthDate { start = max(start, calendar.startOfDay(for: birthDate)) }
        return DateInterval(start: min(start, today), end: end)
    }

    /// What a range really covers: since the last visit, with no visit
    /// logged yet, is the last 2 weeks, and the sentences say so.
    func effective(lastVisit: Date?) -> ChartRange {
        self == .sinceLastVisit && lastVisit == nil ? .twoWeeks : self
    }
}

/// The series behind each chart, as plain values, and the sentence that
/// leads each one. The sentence is worked out from the same numbers the chart
/// draws: commit ce11c14 took the charts out because reading an amount off
/// one at 3 a.m. meant squinting, so every chart now says its number first.
enum CareCharts {
    // MARK: Feeds and intake

    struct IntakeDay: Identifiable, Equatable {
        let day: Date
        let feeds: Int
        let bottles: Int
        let nursing: Int
        let volumeML: Double
        let nursingMinutes: Int
        /// The daily target as it stood at the end of that day.
        let targetML: Double?
        var id: Date { day }
    }

    /// One entry per day that has feeds; a day with nothing logged is a
    /// gap, never a zero.
    static func intake(
        feeds: [FeedEntry],
        weights: [WeightEntry],
        profile: BabyProfile,
        style: FeedingStyle,
        feedsPerDay: Int,
        range: DateInterval,
        calendar: Calendar
    ) -> [IntakeDay] {
        let inRange = feeds.active(for: nil).filter { range.contains($0.startTime) }
        return FeedStats.groupByDay(inRange, calendar: calendar).reversed().map { group in
            let summary = group.summary
            let endOfDay = calendar.date(byAdding: .day, value: 1, to: group.day)?.addingTimeInterval(-1) ?? group.day
            return IntakeDay(
                day: group.day,
                feeds: summary.feedCount,
                bottles: summary.bottleCount,
                nursing: summary.nursingCount,
                volumeML: summary.totalML,
                nursingMinutes: summary.nursingMinutes,
                targetML: target(at: endOfDay, weights: weights, profile: profile, style: style,
                                 feedsPerDay: feedsPerDay, calendar: calendar)
            )
        }
    }

    /// The daily target at a moment, from the weigh-ins made by then.
    static func target(
        at date: Date,
        weights: [WeightEntry],
        profile: BabyProfile,
        style: FeedingStyle,
        feedsPerDay: Int,
        calendar: Calendar
    ) -> Double? {
        let known = weights.active(for: nil).filter { $0.date <= date }.sorted { $0.date > $1.date }
        return FeedingGuidance.currentTarget(weights: known, profile: profile, style: style,
                                             feedsPerDay: feedsPerDay, now: date, calendar: calendar).target?.targetML
    }

    /// A volume chart only means something when there were bottles with an
    /// amount, as on Today's card.
    static func showsVolume(_ days: [IntakeDay]) -> Bool {
        days.contains { $0.volumeML > 0 }
    }

    /// The target line only when bottles were all of it. Nursing isn't
    /// measured, so a mixed-fed baby's bottles against the whole day's target
    /// would draw two weeks of a shortfall that isn't there.
    static func showsTarget(_ days: [IntakeDay]) -> Bool {
        showsVolume(days) && !days.contains { $0.nursing > 0 } && days.contains { $0.targetML != nil }
    }

    /// The days an average should divide by: the ones before `today`, which
    /// isn't over yet and would pull every average down. Today alone still
    /// counts when it's all there is.
    static func completeDays<Day>(_ days: [Day], day: (Day) -> Date, today: Date?) -> [Day] {
        guard let today else { return days }
        let complete = days.filter { day($0) < today }
        return complete.isEmpty ? days : complete
    }

    /// "Nora averaged 7.4 feeds and 20 oz a day over the last 2 weeks, against
    /// a target of about 19 oz." Averaged over the days with feeds, like every
    /// other average in the app, leaving out `today` (the start of it) when
    /// there are full days to go on. With nursing in the mix, the volume is
    /// what the bottles added up to, and says so.
    static func intakeSentence(_ days: [IntakeDay], unit: VolumeUnit, name: String, range: ChartRange,
                               today: Date? = nil) -> String {
        guard !days.isEmpty else { return "No feeds logged \(range.overPhrase)." }
        let averaged = completeDays(days, day: \.day, today: today)
        let count = Double(averaged.count)
        let feeds = Double(averaged.reduce(0) { $0 + $1.feeds }) / count
        let volume = averaged.reduce(0) { $0 + $1.volumeML } / count
        let minutes = Int((Double(averaged.reduce(0) { $0 + $1.nursingMinutes }) / count).rounded())
        let nursed = days.contains { $0.nursing > 0 }
        let lead = "\(name) averaged \(feeds.formatted(.number.precision(.fractionLength(1)))) feeds"

        guard nursed else {
            var sentence = lead
            if volume > 0 { sentence += " and \(unit.format(milliliters: volume))" }
            sentence += " a day \(range.overPhrase)"
            let targets = averaged.compactMap(\.targetML)
            if showsTarget(days), !targets.isEmpty {
                sentence += ", against a target of about \(unit.format(milliliters: targets.reduce(0, +) / Double(targets.count)))"
            }
            return sentence + "."
        }
        var parts: [String] = []
        if volume > 0 { parts.append("\(unit.format(milliliters: volume)) from bottles") }
        if minutes > 0 { parts.append("about \(minutesText(minutes)) of nursing") }
        guard !parts.isEmpty else { return "\(lead) a day \(range.overPhrase)." }
        return "\(lead) a day \(range.overPhrase), with \(parts.joined(separator: " and "))."
    }

    /// "15 min", "1 hr 5 min": a duration that sits in a sentence.
    static func minutesText(_ minutes: Int) -> String {
        guard minutes >= 60 else { return "\(minutes) min" }
        let hours = minutes / 60
        let rest = minutes % 60
        return rest == 0 ? "\(hours) hr" : "\(hours) hr \(rest) min"
    }

    /// "Sep 28", in the app's time zone.
    static func dayLabel(_ date: Date, calendar: Calendar) -> String {
        var style = Date.FormatStyle.dateTime.month(.abbreviated).day()
        style.timeZone = calendar.timeZone
        return date.formatted(style)
    }

    // MARK: Diapers

    struct DiaperDay: Identifiable, Equatable {
        let day: Date
        let wet: Int
        let dirty: Int
        var id: Date { day }
    }

    static func diapers(_ diapers: [DiaperEntry], range: DateInterval, calendar: Calendar) -> [DiaperDay] {
        let inRange = diapers.active(for: nil).filter { range.contains($0.time) }
        return DayGrouping.group(inRange, calendar: calendar) { $0.time }.reversed().map { group in
            let tally = DiaperTally(group.items)
            return DiaperDay(day: group.day, wet: tally.wet, dirty: tally.dirty)
        }
    }

    /// `IntakeGuidance`'s "Fewer than 6 wet diapers a day after the first
    /// week": the line on the chart, from the day it applies.
    static let wetFloor = 6

    static func wetFloorStart(birthDate: Date?, calendar: Calendar) -> Date? {
        birthDate.flatMap { calendar.date(byAdding: .day, value: 7, to: calendar.startOfDay(for: $0)) }
    }

    /// "5.8 wet and 3.1 dirty diapers a day, on the 14 days they were logged."
    /// Leaving out `today` makes it "on the 13 full days logged".
    static func diaperSentence(_ days: [DiaperDay], range: ChartRange, today: Date? = nil) -> String {
        guard !days.isEmpty else { return "No diapers logged \(range.overPhrase)." }
        let averaged = completeDays(days, day: \.day, today: today)
        let count = Double(averaged.count)
        let wet = Double(averaged.reduce(0) { $0 + $1.wet }) / count
        let dirty = Double(averaged.reduce(0) { $0 + $1.dirty }) / count
        let one = averaged.count == 1
        let lead = "\(wet.formatted(.number.precision(.fractionLength(1)))) wet and \(dirty.formatted(.number.precision(.fractionLength(1)))) dirty diapers a day"
        if averaged.count < days.count {
            return "\(lead), on the \(one ? "1 full day" : "\(averaged.count) full days") logged."
        }
        return "\(lead), on the \(one ? "day" : "\(days.count) days") they were logged."
    }

    // MARK: Feed rhythm

    struct FeedPoint: Identifiable, Equatable {
        let day: Date
        /// Hours after midnight, 0 up to 24.
        let hour: Double
        let kind: FeedKind
        let id: UUID
    }

    static func rhythm(_ feeds: [FeedEntry], range: DateInterval, calendar: Calendar) -> [FeedPoint] {
        feeds.active(for: nil).filter { range.contains($0.startTime) }.map { feed in
            let parts = calendar.dateComponents([.hour, .minute], from: feed.startTime)
            return FeedPoint(day: calendar.startOfDay(for: feed.startTime),
                             hour: Double(parts.hour ?? 0) + Double(parts.minute ?? 0) / 60,
                             kind: feed.kind, id: feed.uuid ?? UUID())
        }
    }

    /// "Feeds bunch up in the evening: 35% of them." or, when no part of the
    /// day clearly leads, that they're spread out.
    static func rhythmSentence(_ feeds: [FeedEntry], range: DateInterval, calendar: Calendar) -> String {
        let inRange = feeds.active(for: nil).filter { range.contains($0.startTime) }
        guard !inRange.isEmpty else { return "No feeds logged in this stretch." }
        let breakdown = DayPartBreakdown(inRange, calendar: calendar)
        guard let busiest = breakdown.busiest else {
            return "Feeds are spread through the day and night, with no one part clearly busiest."
        }
        let percent = Int((breakdown.share(busiest) * 100).rounded())
        return "Feeds bunch up \(busiest == .overnight ? "overnight" : "in the \(busiest.title.lowercased())") (\(busiest.hoursText)): \(percent)% of them."
    }

    // MARK: Weight

    struct WeightPoint: Identifiable, Equatable {
        let date: Date
        let grams: Double
        var id: Date { date }
    }

    struct Band: Identifiable, Equatable {
        let date: Date
        let low: Double
        let high: Double
        var id: Date { date }
    }

    struct WeightChart: Equatable {
        var weighIns: [WeightPoint] = []
        /// For the first weeks, while "back to birth weight" is the question.
        var birthGrams: Double?
        /// The WHO 3rd–97th and 15th–85th percentiles, and the median; empty
        /// until sex is known, because the standards are measured apart.
        var outer: [Band] = []
        var inner: [Band] = []
        var median: [WeightPoint] = []
        /// From the last weigh-in to today, along its percentile: dashed.
        var projection: [WeightPoint] = []
        /// From the day of birth (or the first weigh-in, without the curves)
        /// to the end of today, like the Timeline's charts.
        var domain: ClosedRange<Date>?
    }

    static func weight(weights: [WeightEntry], profile: BabyProfile, now: Date, calendar: Calendar) -> WeightChart {
        let sorted = weights.active(for: nil).sorted { $0.date < $1.date }
        var chart = WeightChart(weighIns: sorted.map { WeightPoint(date: $0.date, grams: $0.grams) })
        let endOfToday = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: now)) ?? now
        if let first = sorted.first {
            chart.domain = calendar.startOfDay(for: first.date)...max(endOfToday, sorted.last?.date ?? first.date)
        }

        if let birthDate = profile.birthDate {
            switch BirthWeightStatus(weights: sorted, birthDate: birthDate, calendar: calendar) {
            case .birthOnly(let grams): chart.birthGrams = grams
            case .below(let birth, _, _), .notRegained(let birth, _, _): chart.birthGrams = birth
            case .regained, .noBirthWeight: break
            }
        }

        guard let sex = profile.sex.known, let birthDate = profile.birthDate else { return chart }
        let start = calendar.startOfDay(for: birthDate)
        let end = chart.domain?.upperBound ?? endOfToday
        chart.domain = min(start, chart.domain?.lowerBound ?? start)...end
        // About 40 samples whatever the age, and the last exactly at the end
        // of the axis so the bands reach it.
        let days = max(1, RelativeAge.days(from: start, to: end, calendar: calendar))
        let step = max(1, days / 40)
        var dates = stride(from: 0, to: days, by: step).compactMap { calendar.date(byAdding: .day, value: $0, to: start) }
        dates.append(end)
        // The first sample is the moment of birth, not the midnight before it,
        // which would be an age below zero.
        for date in dates.map({ max($0, birthDate) }) {
            guard let age = profile.growthAgeDays(on: date), age >= 0 else { continue }
            if let p3 = GrowthStandard.grams(percentile: 3, ageDays: age, sex: sex),
               let p97 = GrowthStandard.grams(percentile: 97, ageDays: age, sex: sex) {
                chart.outer.append(Band(date: date, low: p3, high: p97))
            }
            if let p15 = GrowthStandard.grams(percentile: 15, ageDays: age, sex: sex),
               let p85 = GrowthStandard.grams(percentile: 85, ageDays: age, sex: sex) {
                chart.inner.append(Band(date: date, low: p15, high: p85))
            }
            if let p50 = GrowthStandard.grams(percentile: 50, ageDays: age, sex: sex) {
                chart.median.append(WeightPoint(date: date, grams: p50))
            }
        }
        let newestFirst = sorted.reversed().map { $0 }
        if let projection = GrowthProjector.project(weights: newestFirst, profile: profile, now: now, calendar: calendar),
           !projection.isMeasured {
            chart.projection = [WeightPoint(date: projection.anchorDate, grams: projection.anchorGrams),
                                WeightPoint(date: now, grams: projection.estimatedGrams)]
        }
        return chart
    }

    /// "7 lb 9 oz on Sep 28, around the 45th percentile."
    static func weightSentence(weights: [WeightEntry], profile: BabyProfile, weightUnit: WeightUnit, calendar: Calendar) -> String {
        guard let latest = weights.active(for: nil).max(by: { $0.date < $1.date }) else {
            return "No weigh-ins yet."
        }
        var style = Date.FormatStyle.dateTime.month(.abbreviated).day()
        style.timeZone = calendar.timeZone
        var sentence = "\(weightUnit.format(grams: latest.grams)) on \(latest.date.formatted(style))"
        if let sex = profile.sex.known, let age = profile.growthAgeDays(on: latest.date),
           let percentile = GrowthStandard.percentile(grams: latest.grams, ageDays: age, sex: sex) {
            sentence += ", around the \(GrowthProjector.ordinal(percentile: percentile)) percentile"
        }
        return sentence + "."
    }

    // MARK: Care overview

    struct ConcernSpan: Identifiable, Equatable {
        let title: String
        let start: Date
        let end: Date
        let ongoing: Bool
        let id: UUID
    }

    struct DoseMark: Identifiable, Equatable {
        let time: Date
        let name: String
        let id: UUID
    }

    struct VisitMark: Identifiable, Equatable {
        let date: Date
        let title: String
        let id: UUID
    }

    struct Overview: Equatable {
        var concerns: [ConcernSpan] = []
        var doses: [DoseMark] = []
        var visits: [VisitMark] = []
        var feedDays: [IntakeDay] = []
        var diaperDays: [DiaperDay] = []

        /// Nothing in any lane, so there's no chart worth drawing under the sentence.
        var isEmpty: Bool {
            concerns.isEmpty && doses.isEmpty && visits.isEmpty && feedDays.isEmpty && diaperDays.isEmpty
        }
    }

    static func overview(
        concerns: [HealthConcern],
        doses: [MedicationDose],
        visits: [DoctorVisit],
        feedDays: [IntakeDay],
        diaperDays: [DiaperDay],
        range: DateInterval,
        now: Date
    ) -> Overview {
        Overview(
            concerns: concerns.active(for: nil)
                .filter { $0.startedAt < range.end && ($0.resolvedAt ?? now) >= range.start }
                .map { ConcernSpan(title: $0.title.isEmpty ? $0.kind.title : $0.title,
                                   start: max($0.startedAt, range.start),
                                   end: min($0.resolvedAt ?? now, range.end),
                                   ongoing: $0.isOngoing, id: $0.uuid ?? UUID()) },
            doses: doses.active(for: nil).filter { range.contains($0.time) }
                .map { DoseMark(time: $0.time, name: $0.medicationName, id: $0.uuid ?? UUID()) },
            visits: visits.active(for: nil).filter { range.contains($0.date) }
                .map { VisitMark(date: $0.date, title: $0.kind.title, id: $0.uuid ?? UUID()) },
            feedDays: feedDays,
            diaperDays: diaperDays
        )
    }

    /// "1 concern ongoing, 12 doses and 2 visits over the last 2 weeks."
    static func overviewSentence(_ overview: Overview, range: ChartRange) -> String {
        var parts: [String] = []
        let ongoing = overview.concerns.filter(\.ongoing).count
        let ended = overview.concerns.count - ongoing
        if ongoing > 0 { parts.append(ongoing == 1 ? "1 concern ongoing" : "\(ongoing) concerns ongoing") }
        if ended > 0 { parts.append(ended == 1 ? "1 that cleared up" : "\(ended) that cleared up") }
        if !overview.doses.isEmpty { parts.append(overview.doses.count == 1 ? "1 dose" : "\(overview.doses.count) doses") }
        if !overview.visits.isEmpty { parts.append(overview.visits.count == 1 ? "1 visit" : "\(overview.visits.count) visits") }
        guard !parts.isEmpty else { return "No concerns, medicines or visits \(range.overPhrase)." }
        let list = parts.count == 1 ? parts[0] : parts.dropLast().joined(separator: ", ") + " and " + parts.last!
        return "\(list.prefix(1).uppercased())\(list.dropFirst()) \(range.overPhrase)."
    }
}
