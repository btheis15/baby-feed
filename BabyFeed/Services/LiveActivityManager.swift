import ActivityKit
import Foundation

/// Keeps one Live Activity alive showing "last fed X ago · next due at Y".
@MainActor
enum LiveActivityManager {
    static func update(lastFeed: FeedEntry?, dueDate: Date?, unit: VolumeUnit, babyName: String) async {
        let activities = Activity<NextFeedActivityAttributes>.activities

        guard AppSettings.liveActivityEnabled, let lastFeed else {
            for activity in activities {
                await activity.end(nil, dismissalPolicy: .immediate)
            }
            return
        }
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }

        let state = NextFeedActivityAttributes.ContentState(
            lastFeedTime: lastFeed.startTime,
            lastFeedText: "\(lastFeed.kind.title) · \(lastFeed.detailText(unit: unit))",
            kindRaw: lastFeed.kindRaw,
            dueTime: dueDate
        )
        // Mark stale a while after the due time so the system dims it if the app never updates.
        let staleDate = (dueDate ?? lastFeed.startTime.addingTimeInterval(4 * 3600)).addingTimeInterval(2 * 3600)
        let content = ActivityContent(state: state, staleDate: staleDate)

        if let current = activities.first {
            await current.update(content)
            for extra in activities.dropFirst() {
                await extra.end(nil, dismissalPolicy: .immediate)
            }
        } else {
            _ = try? Activity<NextFeedActivityAttributes>.request(
                attributes: NextFeedActivityAttributes(babyName: babyName),
                content: content,
                pushType: nil
            )
        }
    }

    static func endAll() async {
        for activity in Activity<NextFeedActivityAttributes>.activities {
            await activity.end(nil, dismissalPolicy: .immediate)
        }
    }
}
