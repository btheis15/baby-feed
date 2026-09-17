import Foundation

/// Compact "time since" text shared by the app and the widget.
enum ElapsedText {
    /// "Just now", "45m", "1h 23m", "2h", "1d 3h".
    static func compact(since start: Date, now: Date = .now) -> String {
        let totalMinutes = Int(max(0, now.timeIntervalSince(start)) / 60)
        if totalMinutes < 1 { return "Just now" }

        let days = totalMinutes / (24 * 60)
        let hours = (totalMinutes % (24 * 60)) / 60
        let minutes = totalMinutes % 60

        if days > 0 {
            return hours > 0 ? "\(days)d \(hours)h" : "\(days)d"
        }
        if hours > 0 {
            return minutes > 0 ? "\(hours)h \(minutes)m" : "\(hours)h"
        }
        return "\(minutes)m"
    }
}
