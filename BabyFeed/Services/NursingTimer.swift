import Foundation
import Observation
import SwiftData

/// The nursing timer: started from the Nursing sheet, shown in Today's hero
/// and the Live Activity, and saved as an ordinary nursing feed on Done.
@Observable
@MainActor
final class NursingTimer {
    static let shared = NursingTimer()

    private(set) var session: NursingSession? = NursingSession.load()

    private init() {}

    var isRunning: Bool { session != nil }

    func start(side: NursingSide, at date: Date = .now) {
        let session = NursingSession(startedAt: date, side: side == .both ? .left : side)
        session.save()
        self.session = session
        refreshSurroundings()
    }

    func switchSide(at date: Date = .now) {
        session?.switchSide(at: date)
        session?.save()
        refreshSurroundings()
    }

    func cancel() {
        session = nil
        NursingSession.clear()
        refreshSurroundings()
    }

    /// Saves the feed and ends the session. The usual `FeedCoordinator`
    /// path, so the countdown restarts from this feed on every screen.
    @discardableResult
    func finish(at date: Date = .now, in context: ModelContext) -> FeedEntry? {
        guard let session else { return nil }
        let feed = session.feed(endingAt: date, babyID: AppSettings.currentBabyID,
                                loggedByName: AppSettings.displayName)
        context.insert(feed)
        self.session = nil
        NursingSession.clear()
        if let minutes = feed.durationMinutes { FeedDefaults.setDefaultNursingMinutes(minutes) }
        FeedCoordinator.feedsDidChange(in: context)
        return feed
    }

    /// The Live Activity follows the session: it counts nursing minutes while
    /// one runs, and goes back to the countdown after.
    private func refreshSurroundings() {
        FeedCoordinator.feedsDidChange(in: AppModelContainer.shared.mainContext, triggerSync: false)
    }
}
