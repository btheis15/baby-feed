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
