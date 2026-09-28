import ActivityKit
import Foundation

/// Live Activity shown on the Lock Screen and in the Dynamic Island: a
/// countdown to the next feed, and when the last one was.
///
/// It can't run code on a timer. Its text counts down by itself, and its
/// stale date is the due time, so `context.isStale` switches it to "Feed is
/// due" exactly on time with no update from the app.
struct NextFeedActivityAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable {
        var lastFeedTime: Date
        /// "Formula · 3 oz"
        var lastFeedText: String
        var kindRaw: String
        var dueTime: Date?
        /// Pinned in Settings, or nil to follow the device.
        var timeZoneIdentifier: String? = nil
        /// Set while a nursing timer runs: the activity shows "Nursing · Left"
        /// and the minutes since this, instead of the countdown.
        var nursingStartedAt: Date? = nil
        var nursingSideRaw: String? = nil

        var timeZone: TimeZone {
            timeZoneIdentifier.flatMap(TimeZone.init(identifier:)) ?? .current
        }

        var nursingSide: NursingSide? { nursingSideRaw.flatMap(NursingSide.init(rawValue:)) }
    }

    var babyName: String
}
