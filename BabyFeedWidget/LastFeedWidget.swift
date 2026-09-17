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

        // Entries every 10 minutes for the next two hours keep the compact
        // "1h 20m" text fresh on families that can't use live relative text.
        var entries: [LastFeedEntry] = []
        for step in 0..<12 {
            entries.append(LastFeedEntry(date: now.addingTimeInterval(Double(step) * 600), snapshot: snapshot))
        }
        // Also flip exactly at the due time so "Feed is due" appears on time.
        if let due = snapshot.nextFeedDue, due > now, due < now.addingTimeInterval(2 * 3600) {
            entries.append(LastFeedEntry(date: due.addingTimeInterval(1), snapshot: snapshot))
            entries.sort { $0.date < $1.date }
        }
        completion(Timeline(entries: entries, policy: .atEnd))
    }
}

struct LastFeedWidget: Widget {
    let kind = "LastFeedWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: LastFeedProvider()) { entry in
            LastFeedWidgetView(entry: entry)
        }
        .configurationDisplayName("Last Feed")
        .description("How long since the last feed, and when the next one is due.")
        .supportedFamilies([.systemSmall, .systemMedium, .accessoryCircular, .accessoryRectangular, .accessoryInline])
    }
}

struct LastFeedWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: LastFeedEntry

    private var snapshot: FeedSnapshot { entry.snapshot }
    private var kind: FeedKind? { snapshot.lastFeed.flatMap { FeedKind(rawValue: $0.kindRaw) } }
    private var isDue: Bool {
        guard let due = snapshot.nextFeedDue else { return false }
        return due <= entry.date
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
            if let last = snapshot.lastFeed {
                Text(last.time, style: .relative)
                    .font(.title2.weight(.bold))
                    .lineLimit(2)
                    .minimumScaleFactor(0.6)
                    .foregroundStyle(isDue ? Color.orange : Color.primary)
                    .widgetAccentable()
                Text("\(last.title) · \(last.detail)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                Spacer(minLength: 0)
                dueLine
            } else {
                Spacer(minLength: 0)
                Text("No feeds yet")
                    .font(.headline)
                Text("Tap to log one")
                    .font(.caption)
                    .foregroundStyle(.secondary)
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
            Text(isDue ? "Feed is due" : "Since last feed")
                .font(.caption.weight(.medium))
                .foregroundStyle(isDue ? Color.orange : Color.secondary)
        }
    }

    @ViewBuilder
    private var dueLine: some View {
        if let due = snapshot.nextFeedDue {
            HStack(spacing: 4) {
                Image(systemName: "bell.fill")
                    .imageScale(.small)
                if isDue {
                    Text("Due now")
                } else {
                    Text("Next ~\(due, style: .time)")
                }
            }
            .font(.caption.weight(.medium))
            .foregroundStyle(isDue ? Color.orange : Color.secondary)
        } else {
            HStack(spacing: 4) {
                Text("24h: \(snapshot.last24hFeedCount) feeds · \(snapshot.last24hVolumeText)")
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            .lineLimit(1)
        }
    }

    // MARK: Lock Screen

    private var circular: some View {
        ZStack {
            AccessoryWidgetBackground()
            VStack(spacing: 0) {
                Image(systemName: kind?.systemImage ?? "moon.zzz.fill")
                    .font(.caption)
                if let last = snapshot.lastFeed {
                    Text(ElapsedText.compact(since: last.time, now: entry.date))
                        .font(.headline)
                        .minimumScaleFactor(0.5)
                        .lineLimit(1)
                } else {
                    Text("—")
                        .font(.headline)
                }
            }
            .widgetAccentable()
        }
    }

    private var rectangular: some View {
        VStack(alignment: .leading, spacing: 2) {
            if let last = snapshot.lastFeed {
                Text(isDue ? "Feed is due" : "Since last feed")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Text(last.time, style: .relative)
                    .font(.headline)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                    .widgetAccentable()
                Text("\(last.title) · \(last.detail)")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            } else {
                Text("Baby Feed")
                    .font(.headline)
                Text("No feeds logged yet")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var inline: some View {
        Group {
            if let last = snapshot.lastFeed {
                if isDue {
                    Text("Feed due · last \(ElapsedText.compact(since: last.time, now: entry.date)) ago")
                } else {
                    Text("Fed \(ElapsedText.compact(since: last.time, now: entry.date)) ago · \(last.detail)")
                }
            } else {
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
