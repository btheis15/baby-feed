import ActivityKit
import Foundation

/// Live Activity shown on the Lock Screen and in the Dynamic Island:
/// how long since the last feed and when the next one is due.
struct NextFeedActivityAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable {
        var lastFeedTime: Date
        /// "Formula · 3 oz"
        var lastFeedText: String
        var kindRaw: String
        var dueTime: Date?
    }

    var babyName: String
}
