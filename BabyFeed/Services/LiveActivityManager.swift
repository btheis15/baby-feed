import ActivityKit
import Foundation

/// Keeps one Live Activity alive with the countdown to the next feed.
@MainActor
enum LiveActivityManager {
    static func update(lastFeed: FeedEntry?, countdown: FeedCountdown, unit: VolumeUnit, babyName: String) async {
        let all = Activity<NextFeedActivityAttributes>.activities
        // An ended activity can linger in the list. Treating it as the current
        // one meant updating something that no longer shows, and never
        // requesting the one that would.
        let running = all.filter { $0.activityState == .active || $0.activityState == .stale }

        // A nursing timer running: the activity counts its minutes instead,
        // and doesn't go stale at a due time that no longer means anything.
        if AppSettings.liveActivityEnabled, let session = NursingSession.load() {
            guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }
            let state = NextFeedActivityAttributes.ContentState(
                lastFeedTime: lastFeed?.startTime ?? session.startedAt,
                lastFeedText: lastFeed.map { "\($0.kind.title) · \($0.detailText(unit: unit))" } ?? "",
                kindRaw: FeedKind.nursing.rawValue,
                dueTime: nil,
                timeZoneIdentifier: AppSettings.pinnedTimeZoneIdentifier,
                nursingStartedAt: session.startedAt,
                nursingSideRaw: session.side.rawValue
            )
            // Stale a minute in: until then the views say "Just started"
            // rather than a stopwatch reading "0 minutes".
            let content = ActivityContent(state: state, staleDate: session.startedAt.addingTimeInterval(60))
            if let current = running.first {
                if current.content.state != state { await current.update(content) }
                for extra in running.dropFirst() { await extra.end(nil, dismissalPolicy: .immediate) }
            } else {
                _ = try? Activity<NextFeedActivityAttributes>.request(
                    attributes: NextFeedActivityAttributes(babyName: babyName),
                    content: content,
                    pushType: nil
                )
            }
            return
        }

        // Nothing to count down to: no feed yet, switched off in Settings, or
        // gone quiet because nothing has been logged for well over an interval.
        guard AppSettings.liveActivityEnabled, let lastFeed, let due = countdown.due else {
            for activity in all {
                await activity.end(nil, dismissalPolicy: .immediate)
            }
            return
        }
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }

        let state = NextFeedActivityAttributes.ContentState(
            lastFeedTime: lastFeed.startTime,
            lastFeedText: "\(lastFeed.kind.title) · \(lastFeed.detailText(unit: unit))",
            kindRaw: lastFeed.kindRaw,
            dueTime: due,
            timeZoneIdentifier: AppSettings.pinnedTimeZoneIdentifier
        )
        // Stale from the due time: the views read `isStale` and switch to
        // "Feed is due" exactly on time, with no update needed from the app.
        let content = ActivityContent(state: state, staleDate: due)

        // One activity per feed. The system ends a Live Activity after eight
        // hours, so one started at the first feed of the day and updated from
        // then on would quietly disappear by the afternoon. A fresh one for
        // each logged feed never gets near the limit.
        if let current = running.first, current.content.state.lastFeedTime == state.lastFeedTime {
            if current.content.state != state {
                await current.update(content)
            }
            for extra in running.dropFirst() {
                await extra.end(nil, dismissalPolicy: .immediate)
            }
            return
        }

        for activity in all {
            await activity.end(nil, dismissalPolicy: .immediate)
        }
        _ = try? Activity<NextFeedActivityAttributes>.request(
            attributes: NextFeedActivityAttributes(babyName: babyName),
            content: content,
            pushType: nil
        )
    }

    static func endAll() async {
        for activity in Activity<NextFeedActivityAttributes>.activities {
            await activity.end(nil, dismissalPolicy: .immediate)
        }
    }
}
