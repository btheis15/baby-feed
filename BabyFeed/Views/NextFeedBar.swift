import SwiftData
import SwiftUI

/// Content of the tab bar accessory: always-visible "last fed / next due".
struct NextFeedBar: View {
    @Environment(AppRouter.self) private var router
    @Query(sort: \FeedEntry.startTime, order: .reverse) private var entries: [FeedEntry]
    @AppStorage(AppSettings.remindersEnabledKey) private var remindersEnabled = false
    @AppStorage(AppSettings.intervalMinutesKey) private var intervalMinutes = AppSettings.defaultIntervalMinutes
    @AppStorage(FeedDefaults.volumeUnit) private var unitRaw = VolumeUnit.ounces.rawValue

    private var unit: VolumeUnit { VolumeUnit(rawValue: unitRaw) ?? .ounces }

    var body: some View {
        Button {
            router.openLog(kind: entries.first?.kind)
        } label: {
            HStack(spacing: 10) {
                if let last = entries.first {
                    Image(systemName: last.kind.systemImage)
                        .foregroundStyle(last.kind.color)
                    VStack(alignment: .leading, spacing: 0) {
                        HStack(spacing: 4) {
                            Text("Last fed")
                            Text(last.startTime, style: .relative)
                                .fontWeight(.semibold)
                            Text("ago")
                        }
                        .font(.subheadline)
                        .lineLimit(1)
                        if remindersEnabled {
                            let due = last.startTime.addingTimeInterval(Double(intervalMinutes) * 60)
                            Text(due > .now ? "Next around \(due, format: .dateTime.hour().minute())" : "Feed is due")
                                .font(.caption)
                                .foregroundStyle(due > .now ? Color.secondary : Color.orange)
                        } else {
                            Text("\(last.kind.title) · \(last.detailText(unit: unit))")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                } else {
                    Image(systemName: "moon.zzz.fill")
                        .foregroundStyle(.secondary)
                    Text("Log the first feed")
                        .font(.subheadline)
                }
                Spacer(minLength: 0)
                Image(systemName: "plus.circle.fill")
                    .font(.title2)
                    .foregroundStyle(.tint)
            }
            .padding(.horizontal, 14)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Log a feed")
    }
}
