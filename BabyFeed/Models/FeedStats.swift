import Foundation

/// Totals for a group of feeds (a day, or the last 24 hours).
struct FeedSummary: Equatable {
    var feedCount = 0
    var bottleCount = 0
    var totalML: Double = 0
    var nursingCount = 0
    var nursingMinutes = 0

    init() {}

    init(_ entries: [FeedEntry]) {
        for entry in entries {
            feedCount += 1
            switch entry.kind {
            case .formula, .breastMilk:
                bottleCount += 1
                totalML += entry.amountML ?? 0
            case .nursing:
                nursingCount += 1
                nursingMinutes += entry.durationMinutes ?? 0
            }
        }
    }

    /// "5 feeds · 12 oz · 20 min nursing"
    func text(unit: VolumeUnit) -> String {
        var parts = [feedCount == 1 ? "1 feed" : "\(feedCount) feeds"]
        if bottleCount > 0 {
            parts.append(unit.format(milliliters: totalML))
        }
        if nursingMinutes > 0 {
            parts.append("\(nursingMinutes) min nursing")
        }
        return parts.joined(separator: " · ")
    }
}

/// Totals and per-day averages across a window of calendar days.
///
/// Averages divide by the days that actually have feeds logged, not by the
/// length of the window. A day with nothing logged is *missing information*,
/// not a day the baby didn't eat – nobody logs every feed, and treating a gap
/// as a zero both drags the average down and implies a failure that didn't
/// happen. `hasGaps` lets the screen say how many days it averaged over, so
/// the number is transparent rather than quietly different.
struct PeriodAverages: Equatable {
    /// Length of the window asked for, in days.
    var windowDays = 0
    /// Days inside that window with at least one logged feed.
    var daysWithData = 0
    var feedCount = 0
    var totalML: Double = 0
    var nursingMinutes = 0

    var mlPerDay: Double { daysWithData > 0 ? totalML / Double(daysWithData) : 0 }
    var feedsPerDay: Double { daysWithData > 0 ? Double(feedCount) / Double(daysWithData) : 0 }
    var isEmpty: Bool { feedCount == 0 }
    /// True when part of the window has no data, so the average covers less
    /// than it looks like it does.
    var hasGaps: Bool { daysWithData < windowDays }
}

/// Which quarter of the clock a feed falls in.
enum DayPart: String, CaseIterable, Identifiable {
    case overnight
    case morning
    case afternoon
    case evening

    var id: String { rawValue }

    /// The part containing a given hour of day (0–23).
    static func containing(hour: Int) -> DayPart {
        switch hour {
        case 0..<6: .overnight
        case 6..<12: .morning
        case 12..<18: .afternoon
        default: .evening
        }
    }

    var title: String {
        switch self {
        case .overnight: "Overnight"
        case .morning: "Morning"
        case .afternoon: "Afternoon"
        case .evening: "Evening"
        }
    }

    var hoursText: String {
        switch self {
        case .overnight: "12–6 AM"
        case .morning: "6 AM–noon"
        case .afternoon: "Noon–6 PM"
        case .evening: "6 PM–midnight"
        }
    }
}

/// How a set of feeds spreads across the four parts of the day – the numbers
/// behind "is she clustering at night?".
struct DayPartBreakdown: Equatable {
    private var counts: [DayPart: Int] = [:]

    init() {}

    init(_ entries: [FeedEntry], calendar: Calendar = .current) {
        for entry in entries {
            let hour = calendar.component(.hour, from: entry.startTime)
            counts[DayPart.containing(hour: hour), default: 0] += 1
        }
    }

    func count(_ part: DayPart) -> Int { counts[part] ?? 0 }

    var total: Int { counts.values.reduce(0, +) }

    /// Share of all feeds in this part, 0–1.
    func share(_ part: DayPart) -> Double {
        total > 0 ? Double(count(part)) / Double(total) : 0
    }

    /// How far ahead the leading part has to be before it's fair to name it.
    ///
    /// Four parts means an even spread is 25% each. A part on 29% against a
    /// runner-up on 26% is not "mostly" anything, and saying so would invent a
    /// pattern out of noise.
    static let busiestMargin = 0.08

    /// The part with clearly the most feeds, or nil when no part leads by
    /// enough to be worth naming.
    var busiest: DayPart? {
        let ranked = DayPart.allCases
            .map { (part: $0, share: share($0)) }
            .sorted { $0.share > $1.share }
        guard let top = ranked.first, top.share > 0 else { return nil }
        guard ranked.count > 1 else { return top.part }
        return top.share - ranked[1].share >= Self.busiestMargin ? top.part : nil
    }
}

/// Feeds that happened on one calendar day.
struct DayGroup: Identifiable {
    let day: Date
    let entries: [FeedEntry]
    var id: Date { day }
    var summary: FeedSummary { FeedSummary(entries) }
}

/// Pure helpers over feed entries. No SwiftUI, no persistence – easy to test.
enum FeedStats {
    /// Compact elapsed time: "Just now", "45m", "1h 23m", "2h", "1d 3h".
    static func elapsedText(since start: Date, now: Date = .now) -> String {
        ElapsedText.compact(since: start, now: now)
    }

    /// Mean hours between consecutive feeds, or nil with fewer than two feeds.
    static func averageGapHours(_ entries: [FeedEntry]) -> Double? {
        let times = entries.map(\.startTime).sorted()
        guard times.count >= 2 else { return nil }
        var total: TimeInterval = 0
        for index in 1..<times.count {
            total += times[index].timeIntervalSince(times[index - 1])
        }
        return total / Double(times.count - 1) / 3600
    }

    /// Longest gap in hours between consecutive feeds, or nil with fewer than two.
    static func longestGapHours(_ entries: [FeedEntry]) -> Double? {
        let times = entries.map(\.startTime).sorted()
        guard times.count >= 2 else { return nil }
        var longest: TimeInterval = 0
        for index in 1..<times.count {
            longest = max(longest, times[index].timeIntervalSince(times[index - 1]))
        }
        return longest / 3600
    }

    /// "3h 15m" / "45m" from an hour count.
    static func durationText(hours: Double) -> String {
        ElapsedText.compact(minutes: Int((hours * 60).rounded()))
    }

    /// The amount this caregiver actually tends to give for a kind of bottle.
    ///
    /// The median of the most recent feeds rather than the mean, so one 150 ml
    /// outlier or a mis-tapped 10 ml doesn't drag it. Nil until there are
    /// enough feeds to be a habit rather than a coincidence – guessing from two
    /// bottles would make the default jump around.
    ///
    /// - Parameters:
    ///   - recentCount: how many of the latest feeds of that kind to consider.
    ///   - minimumSamples: below this, there's no habit to learn.
    static func typicalAmountML(
        _ entries: [FeedEntry],
        kind: FeedKind,
        recentCount: Int = 10,
        minimumSamples: Int = 4
    ) -> Double? {
        let amounts = entries
            .filter { $0.kind == kind && $0.deletedAt == nil }
            .sorted { $0.startTime > $1.startTime }
            .prefix(recentCount)
            .compactMap(\.amountML)
            .filter { $0 > 0 }

        guard amounts.count >= minimumSamples else { return nil }
        return median(of: amounts)
    }

    /// Middle value, averaging the two middles for an even count.
    static func median(of values: [Double]) -> Double? {
        guard !values.isEmpty else { return nil }
        let sorted = values.sorted()
        let middle = sorted.count / 2
        if sorted.count.isMultiple(of: 2) {
            return (sorted[middle - 1] + sorted[middle]) / 2
        }
        return sorted[middle]
    }

    /// Averages over a window of whole calendar days. `skip` days back from
    /// today are excluded first, then `days` days are measured – so
    /// `days: 7, skip: 1` is the last seven complete days, ending yesterday,
    /// which keeps a partial today from dragging the average down.
    ///
    /// Only days with logged feeds count towards the average; see
    /// `PeriodAverages`.
    static func averages(
        _ groups: [DayGroup],
        days: Int,
        skip: Int = 0,
        calendar: Calendar = .current,
        now: Date = .now
    ) -> PeriodAverages {
        guard days > 0 else { return PeriodAverages() }
        let today = calendar.startOfDay(for: now)
        guard let windowEnd = calendar.date(byAdding: .day, value: -skip, to: today),
              let windowStart = calendar.date(byAdding: .day, value: -(days - 1), to: windowEnd)
        else { return PeriodAverages() }

        var result = PeriodAverages(windowDays: days)
        for group in groups where group.day >= windowStart && group.day <= windowEnd {
            let summary = group.summary
            guard summary.feedCount > 0 else { continue }
            result.daysWithData += 1
            result.feedCount += summary.feedCount
            result.totalML += summary.totalML
            result.nursingMinutes += summary.nursingMinutes
        }
        return result
    }

    /// Entries whose start time is within the trailing window.
    static func entries(_ entries: [FeedEntry], within window: TimeInterval, now: Date = .now) -> [FeedEntry] {
        let cutoff = now.addingTimeInterval(-window)
        return entries.filter { $0.startTime >= cutoff && $0.startTime <= now.addingTimeInterval(60) }
    }

    /// Groups entries by calendar day, newest day first, newest entry first within a day.
    static func groupByDay(_ entries: [FeedEntry], calendar: Calendar = .current) -> [DayGroup] {
        let buckets = Dictionary(grouping: entries) { calendar.startOfDay(for: $0.startTime) }
        return buckets.keys.sorted(by: >).map { day in
            DayGroup(day: day, entries: buckets[day]!.sorted { $0.startTime > $1.startTime })
        }
    }

    /// "Today", "Yesterday", or "Mon, Sep 15".
    static func dayTitle(for day: Date, calendar: Calendar = .current, now: Date = .now) -> String {
        if calendar.isDate(day, inSameDayAs: now) { return "Today" }
        if let yesterday = calendar.date(byAdding: .day, value: -1, to: now),
           calendar.isDate(day, inSameDayAs: yesterday) {
            return "Yesterday"
        }
        let sameYear = calendar.component(.year, from: day) == calendar.component(.year, from: now)
        let style: Date.FormatStyle = sameYear
            ? .dateTime.weekday(.abbreviated).month(.abbreviated).day()
            : .dateTime.weekday(.abbreviated).month(.abbreviated).day().year()
        return day.formatted(style)
    }

    /// Whole log as CSV, newest first. Volumes are exported in the chosen unit.
    static func csv(_ entries: [FeedEntry], unit: VolumeUnit, calendar: Calendar = .current) -> String {
        var lines = ["date,time,kind,amount,unit,duration_min,side,note"]
        let posix = Locale(identifier: "en_US_POSIX")
        let sorted = entries.sorted { $0.startTime > $1.startTime }
        for entry in sorted {
            let c = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: entry.startTime)
            let date = String(format: "%04d-%02d-%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0)
            let time = String(format: "%02d:%02d", c.hour ?? 0, c.minute ?? 0)
            let amount = entry.amountML.map { unit.formatValue(unit.fromMilliliters($0), locale: posix) } ?? ""
            let amountUnit = entry.amountML == nil ? "" : unit.symbol
            let duration = entry.durationMinutes.map(String.init) ?? ""
            let side = entry.side?.rawValue ?? ""
            let note = "\"" + entry.note.replacingOccurrences(of: "\"", with: "\"\"") + "\""
            lines.append([date, time, entry.kind.rawValue, amount, amountUnit, duration, side, note].joined(separator: ","))
        }
        return lines.joined(separator: "\n")
    }
}
