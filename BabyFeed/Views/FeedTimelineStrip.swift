import SwiftUI

/// A 24-hour strip with a dot for each feed, so you can see the rhythm of a day.
struct FeedTimelineStrip: View {
    let entries: [FeedEntry]
    let day: Date
    var calendar: Calendar = .current

    var body: some View {
        VStack(spacing: 4) {
            GeometryReader { geometry in
                let width = geometry.size.width
                let dayStart = calendar.startOfDay(for: day)
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
                    ForEach(entries) { entry in
                        let seconds = entry.startTime.timeIntervalSince(dayStart)
                        let fraction = min(max(seconds / 86_400, 0), 1)
                        Circle()
                            .fill(entry.kind.color)
                            .frame(width: 12, height: 12)
                            .offset(x: width * CGFloat(fraction) - 6)
                    }
                }
                .frame(height: 14)
            }
            .frame(height: 14)

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
        .accessibilityLabel("\(entries.count) feeds during the day")
    }
}
