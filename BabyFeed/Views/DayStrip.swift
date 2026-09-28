import SwiftUI

/// A 24-hour strip for one day: a lane of dots for feeds, and a lane of ticks
/// for diapers underneath, so the rhythm of a day — and a long dry stretch —
/// shows at a glance.
struct DayStrip: View {
    let feeds: [FeedEntry]
    let diapers: [DiaperEntry]
    let day: Date
    var calendar: Calendar = .current

    var body: some View {
        VStack(spacing: 4) {
            GeometryReader { geometry in
                let width = geometry.size.width
                let dayStart = calendar.startOfDay(for: day)
                VStack(alignment: .leading, spacing: 6) {
                    lane(width: width, height: 14) {
                        ForEach(feeds) { feed in
                            Circle()
                                .fill(feed.kind.color)
                                .frame(width: 12, height: 12)
                                .offset(x: x(for: feed.startTime, dayStart: dayStart, width: width) - 6)
                        }
                    }
                    if !diapers.isEmpty {
                        lane(width: width, height: 12) {
                            ForEach(diapers) { diaper in
                                RoundedRectangle(cornerRadius: 1.5)
                                    .fill(diaper.kind.color)
                                    .frame(width: 3, height: 12)
                                    .offset(x: x(for: diaper.time, dayStart: dayStart, width: width) - 1.5)
                            }
                        }
                    }
                }
            }
            .frame(height: diapers.isEmpty ? 14 : 32)

            HStack {
                Text("12 AM")
                Spacer()
                Text("6 AM")
                Spacer()
                Text("Noon")
                Spacer()
                Text("6 PM")
                Spacer()
                Text("12 AM")
            }
            .font(.caption2)
            .foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityText)
    }

    private func x(for time: Date, dayStart: Date, width: CGFloat) -> CGFloat {
        // The day's real length: 23 or 25 hours when the clocks change, so an
        // 11 p.m. feed still lands near the end rather than off it.
        let dayEnd = calendar.date(byAdding: .day, value: 1, to: dayStart) ?? dayStart.addingTimeInterval(86_400)
        let length = max(dayEnd.timeIntervalSince(dayStart), 1)
        let fraction = min(max(time.timeIntervalSince(dayStart) / length, 0), 1)
        return width * CGFloat(fraction)
    }

    private func lane<Content: View>(width: CGFloat, height: CGFloat, @ViewBuilder _ marks: () -> Content) -> some View {
        ZStack(alignment: .leading) {
            Capsule()
                .fill(Color(.tertiarySystemFill))
                .frame(height: 6)
            ForEach([6, 12, 18], id: \.self) { hour in
                Rectangle()
                    .fill(Color.secondary.opacity(0.35))
                    .frame(width: 1, height: 12)
                    .offset(x: width * CGFloat(hour) / 24)
            }
            marks()
        }
        .frame(height: height)
    }

    private var accessibilityText: String {
        let feedText = feeds.count == 1 ? "1 feed" : "\(feeds.count) feeds"
        guard !diapers.isEmpty else { return "\(feedText) during the day" }
        let diaperText = diapers.count == 1 ? "1 diaper" : "\(diapers.count) diapers"
        return "\(feedText) and \(diaperText) during the day"
    }
}
