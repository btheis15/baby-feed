import Foundation

/// Where the next feed stands. The hero on Today, the strip above the tab
/// bar, the widget, the Live Activity and Siri all ask this one question, so
/// this is the one place that answers it and none of them can disagree about
/// whether a feed is due.
///
/// Minutes, never seconds: a parent needs "about an hour and twenty", not a
/// clock ticking in the corner of their eye.
enum FeedCountdown: Equatable {
    /// Nothing logged yet.
    case noFeeds
    /// Due in the future. Rounded up, so it never reads "0m" before it's due.
    case upcoming(due: Date, minutesLeft: Int)
    /// Past due, by up to one whole interval. Rounded down.
    case overdue(due: Date, minutesLate: Int)
    /// More than an interval past due. Either a feed wasn't written down or
    /// logging has tapered off with an older baby — and in both cases a red
    /// timer counting up for days helps nobody, so the app goes quiet.
    case quiet(lastFeed: Date)

    static func nextDue(after lastFeed: Date, intervalMinutes: Int) -> Date {
        lastFeed.addingTimeInterval(Double(max(1, intervalMinutes)) * 60)
    }

    static func state(lastFeed: Date?, intervalMinutes: Int, now: Date) -> FeedCountdown {
        guard let lastFeed else { return .noFeeds }
        let interval = max(1, intervalMinutes)
        let due = nextDue(after: lastFeed, intervalMinutes: interval)
        let seconds = due.timeIntervalSince(now)
        if seconds > 0 {
            // A feed stamped a little in the future — the other phone's clock
            // running fast — still reads as at most one interval away.
            return .upcoming(due: due, minutesLeft: min(interval, Int((seconds / 60).rounded(.up))))
        }
        let late = Int((-seconds / 60).rounded(.down))
        return late <= interval ? .overdue(due: due, minutesLate: late) : .quiet(lastFeed: lastFeed)
    }

    /// For callers that know the last feed and its due time but not the
    /// interval setting, like the widget reading the snapshot.
    static func state(lastFeed: Date?, due: Date?, now: Date) -> FeedCountdown {
        guard let lastFeed else { return .noFeeds }
        guard let due else { return .quiet(lastFeed: lastFeed) }
        let minutes = Int((due.timeIntervalSince(lastFeed) / 60).rounded())
        return state(lastFeed: lastFeed, intervalMinutes: minutes, now: now)
    }

    /// When the next feed is (or was) due; nil when there's nothing to count.
    var due: Date? {
        switch self {
        case .upcoming(let due, _), .overdue(let due, _): due
        case .noFeeds, .quiet: nil
        }
    }

    var isOverdue: Bool {
        if case .overdue = self { true } else { false }
    }

    var isQuiet: Bool {
        if case .quiet = self { true } else { false }
    }

    /// The moments this state changes by itself — at the due time, and an
    /// interval after that when it goes quiet — so a widget timeline only
    /// needs entries there.
    static func transitions(lastFeed: Date, due: Date, after now: Date) -> [Date] {
        let interval = due.timeIntervalSince(lastFeed)
        return [due, due.addingTimeInterval(interval + 60)].filter { $0 > now }
    }
}

/// Clock times in the log's time zone, which may be pinned in Settings.
/// `Date.formatted()` uses the device's zone and would quietly disagree.
enum ClockText {
    static func time(_ date: Date, in timeZone: TimeZone) -> String {
        date.formatted(Date.FormatStyle(date: .omitted, time: .shortened, timeZone: timeZone))
    }

    /// "9:40 AM", "yesterday, 9:40 PM" or "Sep 15", for saying when something
    /// last happened without making anyone work it out.
    static func since(_ date: Date, now: Date, in timeZone: TimeZone) -> String {
        var calendar = Calendar.current
        calendar.timeZone = timeZone
        let clock = time(date, in: timeZone)
        if calendar.isDate(date, inSameDayAs: now) { return clock }
        if let yesterday = calendar.date(byAdding: .day, value: -1, to: now),
           calendar.isDate(date, inSameDayAs: yesterday) {
            return "yesterday, \(clock)"
        }
        return date.formatted(Date.FormatStyle(date: .abbreviated, time: .omitted, timeZone: timeZone))
    }
}
