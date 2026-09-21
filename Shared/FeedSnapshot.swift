import Foundation

/// A small, Codable copy of what the widget and Live Activity need. The app
/// writes it to the App Group after every change so the extension never has
/// to open the SwiftData store.
struct FeedSnapshot: Codable, Equatable {
    struct Feed: Codable, Equatable {
        var time: Date
        var kindRaw: String
        /// "Formula"
        var title: String
        /// "3 oz" or "15 min · Left"
        var detail: String
    }

    var lastFeed: Feed?
    /// When the next feed is due, if reminders are on.
    var nextFeedDue: Date?
    var last24hFeedCount: Int
    /// "14 oz"
    var last24hVolumeText: String
    /// "~20 oz" when a target is known.
    var targetText: String?
    var babyName: String
    var updatedAt: Date

    static let appGroupID = "group.com.babyfeed.shared"
    static let key = "feedSnapshot"

    /// Falls back to standard defaults when the App Group isn't available
    /// (e.g. running on a personal team without the capability).
    static var defaults: UserDefaults {
        UserDefaults(suiteName: appGroupID) ?? .standard
    }

    static func load() -> FeedSnapshot? {
        guard let data = defaults.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(FeedSnapshot.self, from: data)
    }

    func save() {
        if let data = try? JSONEncoder().encode(self) {
            Self.defaults.set(data, forKey: Self.key)
        }
    }

    static let empty = FeedSnapshot(
        lastFeed: nil,
        nextFeedDue: nil,
        last24hFeedCount: 0,
        last24hVolumeText: "0 oz",
        targetText: nil,
        babyName: "Baby",
        updatedAt: .now
    )

    /// Realistic sample for widget placeholders and previews.
    static let placeholder = FeedSnapshot(
        lastFeed: Feed(time: .now.addingTimeInterval(-95 * 60), kindRaw: FeedKind.formula.rawValue, title: "Formula", detail: "3 oz"),
        nextFeedDue: .now.addingTimeInterval(85 * 60),
        last24hFeedCount: 7,
        last24hVolumeText: "18 oz",
        targetText: "~20 oz",
        babyName: "Baby",
        updatedAt: .now
    )
}

/// URLs the widget and notifications use to open the app in the right place.
enum DeepLink {
    static let scheme = "babyfeed"

    static func log(kindRaw: String?) -> URL {
        var string = "\(scheme)://log"
        if let kindRaw { string += "/\(kindRaw)" }
        return URL(string: string)!
    }
}
