import SwiftUI

/// Hero card: how long since the last feed, in very large type.
struct LastFedCard: View {
    let lastFeed: FeedEntry?
    let unit: VolumeUnit
    let now: Date
    /// Turn orange once this much time has passed.
    let nudgeAfter: TimeInterval
    /// When reminders are on, the time the next feed is due.
    let dueDate: Date?
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    /// Icon and text side by side, or stacked once the text needs the full
    /// width of the card to wrap instead of clipping.
    @ViewBuilder
    private func detailRow<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        if dynamicTypeSize.isAccessibilitySize {
            VStack(spacing: 4) { content() }
        } else {
            HStack(spacing: 6) { content() }
        }
    }

    var body: some View {
        VStack(spacing: 8) {
            if let lastFeed {
                let elapsed = now.timeIntervalSince(lastFeed.startTime)

                Text("Since last feed")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.secondary)
                    .textCase(.uppercase)

                Text(FeedStats.elapsedText(since: lastFeed.startTime, now: now))
                    .font(.system(size: 64, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)
                    .foregroundStyle(elapsed >= nudgeAfter ? Color.orange : Color.primary)
                    .contentTransition(.numericText())

                // Icon beside the text normally; above it at accessibility
                // sizes, where a side-by-side row leaves the text too little
                // width and it clips instead of wrapping.
                detailRow {
                    Image(systemName: lastFeed.kind.systemImage)
                        .foregroundStyle(lastFeed.kind.color)
                    Text("\(lastFeed.kind.title) · \(lastFeed.detailText(unit: unit)) · \(lastFeed.startTime.formatted(date: .omitted, time: .shortened))")
                        .fixedSize(horizontal: false, vertical: true)
                }
                .font(.headline)

                if let dueDate {
                    // Built by hand rather than with Label: Label keeps the
                    // icon and title on one line and clips the title mid-word
                    // ("Next feed arour 6:35 PM") when it runs out of room.
                    detailRow {
                        Image(systemName: "bell.fill")
                        Text(dueDate > now
                            ? "Next feed around \(dueDate.formatted(date: .omitted, time: .shortened))"
                            : "Next feed is due")
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .font(.subheadline)
                    .foregroundStyle(dueDate > now ? Color.secondary : Color.orange)
                    .padding(.top, 2)
                }
            } else {
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
        .frame(maxWidth: .infinity)
        .padding(.vertical, 16)
        .multilineTextAlignment(.center)
        .accessibilityElement(children: .combine)
    }
}
