import Foundation

/// Buckets things by calendar day in the log's time zone. Newest day first,
/// newest thing first within a day.
///
/// The same grouping used to be written out three times — History, the
/// diaper list, the food list — each with its own chance to get a pinned
/// time zone or a daylight-saving day wrong.
enum DayGrouping {
    struct Group<Item> {
        let day: Date
        let items: [Item]
    }

    static func group<Item>(_ items: [Item], calendar: Calendar, date: (Item) -> Date) -> [Group<Item>] {
        // Each date is read once. On a SwiftData model every read goes through
        // its backing store, and a sort would read each one many times over.
        let dated = items.map { (date: date($0), item: $0) }
        let buckets = Dictionary(grouping: dated) { calendar.startOfDay(for: $0.date) }
        return buckets.keys.sorted(by: >).map { day in
            Group(day: day, items: buckets[day]!.sorted { $0.date > $1.date }.map(\.item))
        }
    }
}

/// How long ago something happened, the way a doctor asks it: in days.
enum RelativeAge {
    /// Whole calendar days between two moments, in the log's time zone.
    static func days(from start: Date, to end: Date, calendar: Calendar) -> Int {
        calendar.dateComponents([.day], from: calendar.startOfDay(for: start), to: calendar.startOfDay(for: end)).day ?? 0
    }

    /// "Today", "Yesterday", "3 days ago" … "30 days ago", then "5 weeks ago",
    /// then "4 months ago".
    static func ago(_ date: Date, now: Date, calendar: Calendar) -> String {
        let days = days(from: date, to: now, calendar: calendar)
        switch days {
        case ..<1:
            return "Today"
        case 1:
            return "Yesterday"
        case 2...30:
            return "\(days) days ago"
        case 31..<112:
            return "\(days / 7) weeks ago"
        default:
            let months = max(1, calendar.dateComponents([.month], from: date, to: now).month ?? days / 30)
            return months == 1 ? "1 month ago" : "\(months) months ago"
        }
    }

    /// How long something lasted — "lasted 4 days", "lasted about 3 hours" —
    /// or, when it hasn't ended, "ongoing · day 3".
    static func span(start: Date, end: Date?, now: Date, calendar: Calendar) -> String {
        guard let end else {
            return "ongoing · day \(days(from: start, to: now, calendar: calendar) + 1)"
        }
        let days = days(from: start, to: end, calendar: calendar)
        if days >= 1 { return days == 1 ? "lasted 1 day" : "lasted \(days) days" }
        let hours = Int((end.timeIntervalSince(start) / 3600).rounded())
        if hours >= 1 { return hours == 1 ? "lasted about an hour" : "lasted about \(hours) hours" }
        return "lasted under an hour"
    }
}
