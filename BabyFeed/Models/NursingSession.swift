import Foundation

/// A nursing feed in progress: which side, since when, and any switch.
///
/// Kept in UserDefaults rather than the store, so it survives the app being
/// killed mid-feed, and so there's nothing half-made in the log (or on the
/// other phone) until Done saves an ordinary nursing feed.
struct NursingSession: Codable, Equatable {
    var startedAt: Date
    var startSide: NursingSide
    /// The side right now.
    var side: NursingSide
    /// When the side was switched, oldest first.
    var switches: [Date] = []

    init(startedAt: Date, side: NursingSide) {
        self.startedAt = startedAt
        self.startSide = side
        self.side = side
    }

    /// After this long the hero asks "Still nursing?": long feeds happen, but
    /// a timer left running is likelier.
    static let forgottenAfter: TimeInterval = 60 * 60

    mutating func switchSide(at date: Date) {
        side = side == .left ? .right : .left
        switches.append(date)
    }

    /// Whole minutes since it started, at least one: a feed is never "0 min".
    func minutes(at now: Date) -> Int {
        max(1, Int(now.timeIntervalSince(startedAt) / 60))
    }

    /// Minutes on the side it's on now.
    func minutesOnCurrentSide(at now: Date) -> Int {
        max(0, Int(now.timeIntervalSince(switches.last ?? startedAt) / 60))
    }

    func isProbablyForgotten(at now: Date) -> Bool {
        now.timeIntervalSince(startedAt) >= Self.forgottenAfter
    }

    /// The side the saved feed records: both, once it's been switched.
    var feedSide: NursingSide { switches.isEmpty ? startSide : .both }

    /// The feed Done saves: started when the session did, lasting as long.
    func feed(endingAt end: Date, babyID: UUID?, loggedByName: String) -> FeedEntry {
        FeedEntry(
            babyID: babyID,
            startTime: startedAt,
            kind: .nursing,
            durationMinutes: minutes(at: end),
            side: feedSide,
            loggedByName: loggedByName
        )
    }

    // MARK: Persistence

    static let defaultsKey = "nursing.session"

    static func load(from defaults: UserDefaults = .standard) -> NursingSession? {
        guard let data = defaults.data(forKey: defaultsKey) else { return nil }
        return try? JSONDecoder().decode(NursingSession.self, from: data)
    }

    func save(to defaults: UserDefaults = .standard) {
        if let data = try? JSONEncoder().encode(self) { defaults.set(data, forKey: Self.defaultsKey) }
    }

    static func clear(from defaults: UserDefaults = .standard) {
        defaults.removeObject(forKey: defaultsKey)
    }
}

/// The hours "Dark at night" darkens the app: 8 PM to 7 AM by default.
struct NightHours: Equatable {
    /// Minutes after midnight.
    var startMinutes: Int
    var endMinutes: Int

    static let standard = NightHours(startMinutes: 20 * 60, endMinutes: 7 * 60)

    /// Whether a moment falls inside, including the stretch across midnight.
    func contains(_ date: Date, calendar: Calendar) -> Bool {
        let parts = calendar.dateComponents([.hour, .minute], from: date)
        let minute = (parts.hour ?? 0) * 60 + (parts.minute ?? 0)
        if startMinutes == endMinutes { return false }
        if startMinutes < endMinutes { return minute >= startMinutes && minute < endMinutes }
        return minute >= startMinutes || minute < endMinutes
    }

    /// The next time it starts or stops, after `date`: when to look again.
    func nextBoundary(after date: Date, calendar: Calendar) -> Date? {
        let day = calendar.startOfDay(for: date)
        let candidates = (0...2).flatMap { offset -> [Date] in
            guard let base = calendar.date(byAdding: .day, value: offset, to: day) else { return [] }
            return [startMinutes, endMinutes].compactMap {
                calendar.date(bySettingHour: $0 / 60, minute: $0 % 60, second: 0, of: base)
            }
        }
        return candidates.filter { $0 > date }.min()
    }
}
