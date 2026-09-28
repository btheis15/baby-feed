import ActivityKit
import SwiftUI
import WidgetKit

/// Lock Screen banner and Dynamic Island for the countdown to the next feed.
///
/// Everything that moves here is text the system updates by itself, at
/// minute precision — no seconds, and no work for the app. The activity's
/// stale date is the due time, so `isStale` flips it to "Feed is due" exactly
/// when the countdown runs out.
struct NextFeedLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: NextFeedActivityAttributes.self) { context in
            lockScreen(context)
                .padding()
                .activityBackgroundTint(Color(.systemBackground).opacity(0.85))
                .widgetURL(DeepLink.log(kindRaw: nil))
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    HStack(spacing: 6) {
                        icon(context)
                        Text(title(context))
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(isDue(context) ? Color.red : Color.primary)
                            .lineLimit(1)
                    }
                }
                DynamicIslandExpandedRegion(.trailing) {
                    if let started = context.state.nursingStartedAt {
                        nursingMinutes(since: started)
                            .font(.headline)
                    } else if let due = context.state.dueTime {
                        VStack(alignment: .trailing, spacing: 0) {
                            countdown(context, due: due)
                                .font(.headline)
                            Text(clock(due, context))
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                DynamicIslandExpandedRegion(.bottom) {
                    HStack {
                        Text(context.state.nursingStartedAt.map { "Started \(clock($0, context))" }
                             ?? "Last fed \(clock(context.state.lastFeedTime, context)) · \(context.state.lastFeedText)")
                            .lineLimit(1)
                        Spacer()
                        Link(destination: DeepLink.log(kindRaw: nil)) {
                            Label("Log", systemImage: "plus.circle.fill")
                                .font(.caption.weight(.semibold))
                        }
                    }
                    .font(.caption)
                }
            } compactLeading: {
                icon(context)
            } compactTrailing: {
                Group {
                    if let started = context.state.nursingStartedAt {
                        nursingMinutes(since: started)
                    } else {
                        compactCountdown(context)
                    }
                }
                .frame(maxWidth: 56)
                .multilineTextAlignment(.trailing)
            } minimal: {
                icon(context)
            }
            .widgetURL(DeepLink.log(kindRaw: nil))
        }
    }

    // MARK: Pieces

    private func kind(_ context: ActivityViewContext<NextFeedActivityAttributes>) -> FeedKind {
        FeedKind(rawValue: context.state.kindRaw) ?? .formula
    }

    private func icon(_ context: ActivityViewContext<NextFeedActivityAttributes>) -> some View {
        Image(systemName: kind(context).systemImage)
            .foregroundStyle(kind(context).color)
    }

    private func isDue(_ context: ActivityViewContext<NextFeedActivityAttributes>) -> Bool {
        guard context.state.nursingStartedAt == nil else { return false }
        return context.isStale || context.state.dueTime == nil
    }

    private func title(_ context: ActivityViewContext<NextFeedActivityAttributes>) -> String {
        if context.state.nursingStartedAt != nil {
            return context.state.nursingSide.map { "Nursing · \($0.title)" } ?? "Nursing"
        }
        return isDue(context) ? "Feed is due" : "Next feed"
    }

    /// "12:00", counting up in whole minutes: the system updates it, the app
    /// doesn't.
    private func nursingMinutes(since start: Date) -> some View {
        Text(.currentDate, format: .stopwatch(startingAt: start, showsHours: true, maxFieldCount: 2,
                                              maxPrecision: .seconds(60)))
            .monospacedDigit()
    }

    private func clock(_ date: Date, _ context: ActivityViewContext<NextFeedActivityAttributes>) -> String {
        ClockText.time(date, in: context.state.timeZone)
    }

    /// "in 1 hr, 20 min", updated by the system once a minute; "Due" once it's run out.
    @ViewBuilder
    private func countdown(_ context: ActivityViewContext<NextFeedActivityAttributes>, due: Date) -> some View {
        if isDue(context) {
            Text("Due")
                .foregroundStyle(.red)
        } else {
            Text(.currentDate, format: .reference(to: due, allowedFields: [.hour, .minute], maxFieldCount: 2))
                .monospacedDigit()
        }
    }

    /// The Dynamic Island's compact slot is narrow: "1:20", at minute precision.
    @ViewBuilder
    private func compactCountdown(_ context: ActivityViewContext<NextFeedActivityAttributes>) -> some View {
        if let due = context.state.dueTime, !isDue(context), context.state.lastFeedTime < due {
            Text(.currentDate, format: .timer(
                countingDownIn: context.state.lastFeedTime..<due,
                showsHours: true,
                maxFieldCount: 2,
                maxPrecision: .seconds(60)
            ))
            .monospacedDigit()
        } else {
            Text("Due")
                .foregroundStyle(.red)
        }
    }

    private func lockScreen(_ context: ActivityViewContext<NextFeedActivityAttributes>) -> some View {
        HStack(spacing: 14) {
            Image(systemName: kind(context).systemImage)
                .font(.title2)
                .foregroundStyle(.white)
                .frame(width: 44, height: 44)
                .background(kind(context).color, in: Circle())

            VStack(alignment: .leading, spacing: 2) {
                if let started = context.state.nursingStartedAt {
                    Text(title(context))
                        .font(.subheadline.weight(.semibold))
                    Text("Started \(clock(started, context))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else if let due = context.state.dueTime, !isDue(context) {
                    Text("Next feed · around \(clock(due, context))")
                        .font(.subheadline.weight(.semibold))
                } else {
                    Text("Feed is due")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.red)
                }
                if context.state.nursingStartedAt == nil {
                    Text("Last fed \(clock(context.state.lastFeedTime, context)) · \(context.state.lastFeedText)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }

            Spacer(minLength: 8)

            if let started = context.state.nursingStartedAt {
                nursingMinutes(since: started)
                    .font(.title3.weight(.semibold))
                    .multilineTextAlignment(.trailing)
            } else if let due = context.state.dueTime {
                countdown(context, due: due)
                    .font(.title3.weight(.semibold))
                    .multilineTextAlignment(.trailing)
            }
        }
    }
}
