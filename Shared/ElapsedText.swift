import Foundation

/// Compact "time since" text shared by the app and the widget.
enum ElapsedText {
    /// "Just now", "45m", "1h 23m", "2h", "1d 3h".
    static func compact(since start: Date, now: Date = .now) -> String {
        let totalMinutes = Int(max(0, now.timeIntervalSince(start)) / 60)
        if totalMinutes < 1 { return "Just now" }
        return compact(minutes: totalMinutes)
    }

    /// "45m", "1h 23m", "2h", "1d 3h" from a plain minute count.
    /// Used for gaps and stretches, where "Just now" would make no sense.
    static func compact(minutes totalMinutes: Int) -> String {
        let total = max(0, totalMinutes)
        let days = total / (24 * 60)
        let hours = (total % (24 * 60)) / 60
        let minutes = total % 60

        if days > 0 {
            return hours > 0 ? "\(days)d \(hours)h" : "\(days)d"
        }
        if hours > 0 {
            return minutes > 0 ? "\(hours)h \(minutes)m" : "\(hours)h"
        }
        return "\(minutes)m"
    }
}
