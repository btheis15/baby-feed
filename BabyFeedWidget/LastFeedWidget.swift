import SwiftUI
import WidgetKit

struct LastFeedEntry: TimelineEntry {
    let date: Date
    let snapshot: FeedSnapshot
}

struct LastFeedProvider: TimelineProvider {
    func placeholder(in context: Context) -> LastFeedEntry {
        LastFeedEntry(date: .now, snapshot: .placeholder)
    }

    func getSnapshot(in context: Context, completion: @escaping (LastFeedEntry) -> Void) {
        let snapshot = context.isPreview ? FeedSnapshot.placeholder : (FeedSnapshot.load() ?? .empty)
        completion(LastFeedEntry(date: .now, snapshot: snapshot))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<LastFeedEntry>) -> Void) {
        let snapshot = FeedSnapshot.load() ?? .empty
        let now = Date.now

        // The countdown text updates itself, a minute at a time, so entries
        // are only needed where the widget changes what it says: at the due
        // time ("Feed is due"), and an interval later, when it goes quiet.
        // The app reloads the timeline whenever a feed is logged.
        var entries = [LastFeedEntry(date: now, snapshot: snapshot)]
        if let last = snapshot.lastFeed, let due = snapshot.nextFeedDue {
            entries += FeedCountdown.transitions(lastFeed: last.time, due: due, after: now)
                .map { LastFeedEntry(date: $0, snapshot: snapshot) }
        }
        completion(Timeline(entries: entries, policy: .never))
    }
}

struct LastFeedWidget: Widget {
    let kind = "LastFeedWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: LastFeedProvider()) { entry in
            LastFeedWidgetView(entry: entry)
        }
        .configurationDisplayName("Next Feed")
        .description("When the next feed is due, and when the last one was.")
        .supportedFamilies([.systemSmall, .systemMedium, .accessoryCircular, .accessoryRectangular, .accessoryInline])
    }
}

struct LastFeedWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: LastFeedEntry

    private var snapshot: FeedSnapshot { entry.snapshot }
    private var kind: FeedKind? { snapshot.lastFeed.flatMap { FeedKind(rawValue: $0.kindRaw) } }
    private var countdown: FeedCountdown {
        FeedCountdown.state(lastFeed: snapshot.lastFeed?.time, due: snapshot.nextFeedDue, now: entry.date)
    }

    private func clock(_ date: Date) -> String {
        ClockText.time(date, in: snapshot.timeZone)
    }

    var body: some View {
        Group {
            switch family {
            case .accessoryInline:
                inline
            case .accessoryCircular:
                circular
            case .accessoryRectangular:
                rectangular
            case .systemMedium:
                medium
            default:
                small
            }
        }
        .containerBackground(for: .widget) {
            Color(.systemBackground)
        }
        .widgetURL(DeepLink.log(kindRaw: nil))
    }

    // MARK: Home Screen

    private var small: some View {
        VStack(alignment: .leading, spacing: 4) {
            header
            switch countdown {
            case .upcoming(let due, _):
                Text(.currentDate, format: FeedCountdown.timeLeftFormat(to: due))
                    .font(.title2.weight(.bold))
                    .lineLimit(2)
                    .minimumScaleFactor(0.6)
                    .widgetAccentable()
                Text("around \(clock(due))")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
            case .overdue(let due, _):
                Text("Due \(clock(due))")
                    .font(.title2.weight(.bold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                    .foregroundStyle(.red)
                    .widgetAccentable()
                Text(.currentDate, format: .reference(to: due, allowedFields: [.hour, .minute], maxFieldCount: 2))
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
            case .quiet(let last):
                Text(ClockText.since(last, now: entry.date, in: snapshot.timeZone))
                    .font(.title3.weight(.bold))
                    .lineLimit(2)
                    .minimumScaleFactor(0.6)
            case .noFeeds:
                Spacer(minLength: 0)
                Text("No feeds yet")
                    .font(.headline)
                Text("Tap to log one")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
            if let last = snapshot.lastFeed {
                // Two lines: on one, "Nursing · 1 min · Both · 11:51 AM" lost
                // its time, the part that matters most.
                Text("\(last.title) · \(last.detail) · \(clock(last.time))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .minimumScaleFactor(0.8)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var medium: some View {
        HStack(alignment: .top, spacing: 16) {
            small
            VStack(spacing: 8) {
                ForEach(FeedKind.allCases) { kind in
                    Link(destination: DeepLink.log(kindRaw: kind.rawValue)) {
                        HStack {
                            Image(systemName: kind.systemImage)
                            Text(kind.title)
                                .lineLimit(1)
                            Spacer(minLength: 0)
                        }
                        .font(.subheadline.weight(.semibold))
                        .padding(.horizontal, 12)
                        .frame(maxWidth: .infinity, minHeight: 34)
                        .background(kind.color.opacity(0.18), in: Capsule())
                        .foregroundStyle(kind.color)
                    }
                }
            }
            .frame(width: 140)
        }
    }

    private var header: some View {
        HStack(spacing: 4) {
            Image(systemName: kind?.systemImage ?? "moon.zzz.fill")
                .foregroundStyle(kind?.color ?? .secondary)
            Text(headerText)
                .font(.caption.weight(.medium))
                .foregroundStyle(countdown.isOverdue ? Color.red : Color.secondary)
        }
    }

    private var headerText: String {
        switch countdown {
        case .upcoming: "Next feed"
        case .overdue: "Feed is due"
        case .quiet: "Last feed"
        case .noFeeds: "Baby Feed"
        }
    }

    // MARK: Lock Screen

    private var circular: some View {
        ZStack {
            AccessoryWidgetBackground()
            VStack(spacing: 0) {
                Image(systemName: kind?.systemImage ?? "moon.zzz.fill")
                    .font(.caption)
                switch countdown {
                case .upcoming(let due, _):
                    // The due time: a minute-precision countdown spells its
                    // units out ("3 hours, 9 minutes"), far too wide for a circle.
                    Text(clock(due))
                        .font(.headline)
                        .monospacedDigit()
                        .minimumScaleFactor(0.5)
                        .lineLimit(1)
                case .overdue:
                    Text("Due")
                        .font(.headline)
                case .quiet, .noFeeds:
                    Text("—")
                        .font(.headline)
                }
            }
            .widgetAccentable()
        }
    }

    private var rectangular: some View {
        VStack(alignment: .leading, spacing: 2) {
            switch countdown {
            case .upcoming(let due, _):
                Text("Next feed · \(clock(due))")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Text(.currentDate, format: FeedCountdown.timeLeftFormat(to: due))
                    .font(.headline)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                    .widgetAccentable()
            case .overdue(let due, _):
                Text("was due \(clock(due))")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Text("Feed is due")
                    .font(.headline)
                    .widgetAccentable()
            case .quiet(let last):
                Text("Last fed")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Text(ClockText.since(last, now: entry.date, in: snapshot.timeZone))
                    .font(.headline)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            case .noFeeds:
                Text("Baby Feed")
                    .font(.headline)
                Text("No feeds logged yet")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            if let last = snapshot.lastFeed, !countdown.isQuiet {
                Text("\(last.title) · \(last.detail) · \(clock(last.time))")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var inline: some View {
        Group {
            switch countdown {
            case .upcoming(let due, _):
                Text("Next feed ~\(clock(due))")
            case .overdue(let due, _):
                Text("Feed due since \(clock(due))")
            case .quiet(let last):
                Text("Last fed \(ClockText.since(last, now: entry.date, in: snapshot.timeZone))")
            case .noFeeds:
                Text("No feeds logged yet")
            }
        }
    }
}

#Preview("Small", as: .systemSmall) {
    LastFeedWidget()
} timeline: {
    LastFeedEntry(date: .now, snapshot: .placeholder)
    LastFeedEntry(date: .now, snapshot: .empty)
}

#Preview("Medium", as: .systemMedium) {
    LastFeedWidget()
} timeline: {
    LastFeedEntry(date: .now, snapshot: .placeholder)
}

#Preview("Rectangular", as: .accessoryRectangular) {
    LastFeedWidget()
} timeline: {
    LastFeedEntry(date: .now, snapshot: .placeholder)
}
