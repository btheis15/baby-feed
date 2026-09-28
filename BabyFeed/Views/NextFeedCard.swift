import SwiftUI

/// The hero on Today: how long until the next feed, in very large type.
///
/// It used to be a clock counting up from the last feed, which is a number a
/// parent then has to do arithmetic on. The question at 3 a.m. is "how long
/// have I got?", so that's the big number, and when the last feed was sits
/// underneath it, small. It changes once a minute; nothing here ticks seconds.
struct NextFeedCard: View {
    let lastFeed: FeedEntry?
    let countdown: FeedCountdown
    let unit: VolumeUnit
    let now: Date
    let timeZone: TimeZone
    /// A newborn who's gone this long since a feed is usually woken for one.
    let showsNewbornWakeLine: Bool
    let onLog: () -> Void

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        VStack(spacing: 8) {
            switch countdown {
            case .noFeeds:
                emptyState
            case .upcoming(let due, let minutesLeft):
                caption("Next feed in", color: .secondary)
                bigNumber(ElapsedText.compact(minutes: minutesLeft), color: .primary)
                Text("around \(ClockText.time(due, in: timeZone))")
                    .font(.title3.weight(.medium))
                    .foregroundStyle(.secondary)
                lastFedLine
            case .overdue(let due, let minutesLate):
                caption("Overdue", color: .red)
                bigNumber(minutesLate == 0 ? "Now" : ElapsedText.compact(minutes: minutesLate), color: .red)
                Text("was due at \(ClockText.time(due, in: timeZone))")
                    .font(.title3.weight(.medium))
                    .foregroundStyle(.secondary)
                lastFedLine
            case .quiet(let lastFeedTime):
                Image(systemName: "clock.badge.questionmark")
                    .font(.system(size: 36))
                    .foregroundStyle(.secondary)
                Text("No feed logged since \(ClockText.since(lastFeedTime, now: now, in: timeZone))")
                    .font(.title3.weight(.semibold))
                    .fixedSize(horizontal: false, vertical: true)
                Button("Log a feed", action: onLog)
                    .buttonStyle(.borderedProminent)
                    .padding(.top, 4)
            }

            if showsNewbornWakeLine {
                detailRow {
                    Image(systemName: "moon.stars.fill")
                    Text("Newborns are usually woken to feed after about 4 hours until they're back to birth weight.")
                        .fixedSize(horizontal: false, vertical: true)
                }
                .font(.footnote)
                .foregroundStyle(.secondary)
                .padding(.top, 4)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 16)
        .multilineTextAlignment(.center)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityText)
    }

    // MARK: Pieces

    private func caption(_ text: String, color: Color) -> some View {
        Text(text)
            .font(.subheadline.weight(.medium))
            .foregroundStyle(color)
            .textCase(.uppercase)
    }

    private func bigNumber(_ text: String, color: Color) -> some View {
        Text(text)
            .font(.system(size: 64, weight: .bold, design: .rounded))
            .monospacedDigit()
            .lineLimit(1)
            .minimumScaleFactor(0.5)
            .foregroundStyle(color)
            .contentTransition(.numericText())
    }

    /// "Last fed 2:10 PM · Formula 3 oz · 1h 40m ago", small, under the number.
    @ViewBuilder
    private var lastFedLine: some View {
        if let lastFeed {
            detailRow {
                Image(systemName: lastFeed.kind.systemImage)
                    .foregroundStyle(lastFeed.kind.color)
                Text("Last fed \(ClockText.time(lastFeed.startTime, in: timeZone)) · \(lastFeed.kind.title) \(unbroken(lastFeed.detailText(unit: unit))) · \(unbroken(ElapsedText.compact(since: lastFeed.startTime, now: now) + " ago"))")
                    .fixedSize(horizontal: false, vertical: true)
            }
            .font(.subheadline)
            .foregroundStyle(.secondary)
            .padding(.top, 2)
        }
    }

    /// Keeps "1h 38m ago" and "2.7 oz" in one piece when the line wraps.
    private func unbroken(_ text: String) -> String {
        text.replacingOccurrences(of: " ", with: "\u{00A0}")
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "moon.zzz.fill")
                .font(.system(size: 44))
                .foregroundStyle(.secondary)
            Text("No feeds yet")
                .font(.title2.weight(.semibold))
            Text("Tap a button below to log the first one.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }

    /// Icon beside the text normally; above it at accessibility sizes, where a
    /// side-by-side row leaves the text too little width and it clips.
    @ViewBuilder
    private func detailRow<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        if dynamicTypeSize.isAccessibilitySize {
            VStack(spacing: 4) { content() }
        } else {
            HStack(alignment: .firstTextBaseline, spacing: 6) { content() }
        }
    }

    // MARK: VoiceOver

    private var accessibilityText: String {
        var parts: [String] = []
        switch countdown {
        case .noFeeds:
            return "No feeds yet. Tap a button below to log the first one."
        case .upcoming(let due, let minutesLeft):
            parts.append("Next feed in \(ElapsedText.spoken(minutes: minutesLeft)), around \(ClockText.time(due, in: timeZone)).")
        case .overdue(let due, let minutesLate):
            parts.append(minutesLate == 0
                ? "The next feed is due now."
                : "The next feed is \(ElapsedText.spoken(minutes: minutesLate)) overdue. It was due at \(ClockText.time(due, in: timeZone)).")
        case .quiet(let lastFeedTime):
            parts.append("No feed logged since \(ClockText.since(lastFeedTime, now: now, in: timeZone)).")
        }
        if let lastFeed, !countdown.isQuiet {
            parts.append("Last fed at \(ClockText.time(lastFeed.startTime, in: timeZone)), \(lastFeed.kind.title.lowercased()), \(lastFeed.detailText(unit: unit)).")
        }
        if showsNewbornWakeLine {
            parts.append("Newborns are usually woken to feed after about 4 hours until they're back to birth weight.")
        }
        return parts.joined(separator: " ")
    }
}
