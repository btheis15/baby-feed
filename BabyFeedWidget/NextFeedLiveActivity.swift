import ActivityKit
import SwiftUI
import WidgetKit

/// Lock Screen banner and Dynamic Island for the running "next feed" countdown.
struct NextFeedLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: NextFeedActivityAttributes.self) { context in
            lockScreen(context)
                .padding()
                .activityBackgroundTint(Color(.systemBackground).opacity(0.85))
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    HStack(spacing: 6) {
                        Image(systemName: kind(for: context).systemImage)
                            .foregroundStyle(kind(for: context).color)
                        Text(context.state.lastFeedText)
                            .font(.caption)
                            .lineLimit(1)
                    }
                }
                DynamicIslandExpandedRegion(.trailing) {
                    if let due = context.state.dueTime {
                        VStack(alignment: .trailing, spacing: 0) {
                            Text("Next feed")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                            Text(due, style: .time)
                                .font(.caption.weight(.semibold))
                        }
                    }
                }
                DynamicIslandExpandedRegion(.bottom) {
                    HStack {
                        Text("Last fed")
                        Text(context.state.lastFeedTime, style: .relative)
                            .fontWeight(.semibold)
                        Text("ago")
                        Spacer()
                        Link(destination: DeepLink.log(kindRaw: nil)) {
                            Label("Log", systemImage: "plus.circle.fill")
                                .font(.caption.weight(.semibold))
                        }
                    }
                    .font(.caption)
                }
            } compactLeading: {
                Image(systemName: kind(for: context).systemImage)
                    .foregroundStyle(kind(for: context).color)
            } compactTrailing: {
                if let due = context.state.dueTime {
                    Text(due, style: .timer)
                        .monospacedDigit()
                        .frame(maxWidth: 56)
                        .multilineTextAlignment(.trailing)
                } else {
                    Text(context.state.lastFeedTime, style: .timer)
                        .monospacedDigit()
                        .frame(maxWidth: 56)
                        .multilineTextAlignment(.trailing)
                }
            } minimal: {
                Image(systemName: kind(for: context).systemImage)
                    .foregroundStyle(kind(for: context).color)
            }
            .widgetURL(DeepLink.log(kindRaw: nil))
        }
    }

    private func kind(for context: ActivityViewContext<NextFeedActivityAttributes>) -> FeedKind {
        FeedKind(rawValue: context.state.kindRaw) ?? .formula
    }

    private func lockScreen(_ context: ActivityViewContext<NextFeedActivityAttributes>) -> some View {
        HStack(spacing: 14) {
            Image(systemName: kind(for: context).systemImage)
                .font(.title2)
                .foregroundStyle(.white)
                .frame(width: 44, height: 44)
                .background(kind(for: context).color, in: Circle())

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 4) {
                    Text("Last fed")
                    Text(context.state.lastFeedTime, style: .relative)
                        .fontWeight(.semibold)
                    Text("ago")
                }
                .font(.subheadline)
                Text(context.state.lastFeedText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            if let due = context.state.dueTime {
                VStack(alignment: .trailing, spacing: 2) {
                    Text("Next feed")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    Text(due, style: .time)
                        .font(.headline)
                    Text(due, style: .timer)
                        .font(.caption)
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                }
            }
        }
    }
}
