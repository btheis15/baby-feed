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
            ActivityFamilyContent {
                watch(context)
            } medium: {
                lockScreen(context)
                    .padding()
            }
            .activityBackgroundTint(Color(.systemBackground).opacity(0.85))
            // The quick menu, not straight into a formula sheet: a tap here is
            // as often a diaper as a feed.
            .widgetURL(DeepLink.quickLog)
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
                        nursingMinutes(context, since: started)
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
                        Link(destination: DeepLink.quickLog) {
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
                        nursingMinutes(context, since: started, compact: true)
                    } else {
                        compactCountdown(context)
                    }
                }
                .frame(maxWidth: 56)
                .multilineTextAlignment(.trailing)
            } minimal: {
                icon(context)
            }
            .widgetURL(DeepLink.quickLog)
        }
        // The Watch's Smart Stack gets its own layout: by default it showed
        // only the compact island's two ends, the due time and no last feed.
        .supplementalActivityFamilies([.small])
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

    /// "12 minutes", counting up in whole minutes: the system updates it, the
    /// app doesn't. At minute precision the stopwatch spells its units out,
    /// so the compact island gets one unit, shrunk to fit if it has to.
    ///
    /// The first minute would read "0 minutes", so until the activity goes
    /// stale (a minute after the start, see `LiveActivityManager`) it says
    /// "Just started" instead, the way Today's hero never shows a zero.
    @ViewBuilder
    private func nursingMinutes(_ context: ActivityViewContext<NextFeedActivityAttributes>, since start: Date,
                                compact: Bool = false) -> some View {
        if !context.isStale {
            Text(compact ? "Now" : "Just started")
                .lineLimit(1)
                .minimumScaleFactor(compact ? 0.6 : 0.8)
        } else {
            Text(.currentDate, format: .stopwatch(startingAt: start, showsHours: true, maxFieldCount: compact ? 1 : 2,
                                                  maxPrecision: .seconds(60)))
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(compact ? 0.6 : 0.8)
        }
    }

    private func clock(_ date: Date, _ context: ActivityViewContext<NextFeedActivityAttributes>) -> String {
        ClockText.time(date, in: context.state.timeZone)
    }

    /// "1 hour, 20 minutes", updated by the system once a minute; "Due" once
    /// it's run out.
    @ViewBuilder
    private func countdown(_ context: ActivityViewContext<NextFeedActivityAttributes>, due: Date) -> some View {
        if isDue(context) {
            Text("Due")
                .foregroundStyle(.red)
        } else {
            Text(.currentDate, format: FeedCountdown.timeLeftFormat(to: due))
                .monospacedDigit()
                .lineLimit(2)
                .minimumScaleFactor(0.7)
        }
    }

    /// The Dynamic Island's compact slot is narrow, so it shows when the feed
    /// is due, "3:21 PM". A minute-precision countdown spells its units out
    /// and came out as "3 hou…"; the expanded island and the Lock Screen keep
    /// the countdown.
    @ViewBuilder
    private func compactCountdown(_ context: ActivityViewContext<NextFeedActivityAttributes>) -> some View {
        if let due = context.state.dueTime, !isDue(context) {
            Text(clock(due, context))
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        } else {
            Text("Due")
                .foregroundStyle(.red)
        }
    }

    /// The Apple Watch Smart Stack: the same three things as the Lock Screen,
    /// what's next, how long until it, and the last feed, stacked to fit about
    /// 170 × 75 points.
    private func watch(_ context: ActivityViewContext<NextFeedActivityAttributes>) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 4) {
                icon(context)
                Text(title(context))
                    .foregroundStyle(isDue(context) ? Color.red : Color.primary)
            }
            .font(.caption2.weight(.semibold))
            .lineLimit(1)

            Group {
                if let started = context.state.nursingStartedAt {
                    nursingMinutes(context, since: started)
                } else if let due = context.state.dueTime {
                    if isDue(context) {
                        Text("Due")
                            .foregroundStyle(.red)
                    } else {
                        Text("\(clock(due, context)) · \(Text(.currentDate, format: FeedCountdown.timeLeftFormat(to: due)))")
                    }
                }
            }
            .font(.headline)
            .monospacedDigit()
            .lineLimit(1)
            .minimumScaleFactor(0.6)

            Text(context.state.nursingStartedAt.map { "Started \(clock($0, context))" }
                 ?? "Last \(clock(context.state.lastFeedTime, context)) · \(context.state.lastFeedText)")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 4)
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
                nursingMinutes(context, since: started)
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

/// Picks the layout for where the activity is showing: `.small` is the Apple
/// Watch Smart Stack (and CarPlay), `.medium` the iPhone Lock Screen.
private struct ActivityFamilyContent<Small: View, Medium: View>: View {
    @Environment(\.activityFamily) private var family
    @ViewBuilder let small: Small
    @ViewBuilder let medium: Medium

    var body: some View {
        switch family {
        case .small: small
        default: medium
        }
    }
}
