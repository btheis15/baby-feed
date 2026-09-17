import SwiftData
import SwiftUI

/// Content of the tab bar accessory: always-visible "last fed / next due".
struct NextFeedBar: View {
    @Environment(AppRouter.self) private var router
    @Query(sort: \FeedEntry.startTime, order: .reverse) private var entries: [FeedEntry]
    @AppStorage(AppSettings.remindersEnabledKey) private var remindersEnabled = false
    /// 0 means "follow what's typical for this age"; resolved below.
    @AppStorage(AppSettings.intervalMinutesKey) private var intervalMinutesRaw = 0
    /// Read so the bar re-renders as the baby's age moves the interval.
    @AppStorage(BabyProfile.birthDateKey) private var birthInterval: Double = 0
    @AppStorage(FeedDefaults.volumeUnit) private var unitRaw = VolumeUnit.ounces.rawValue
    @AppStorage(AppSettings.currentBabyIDKey) private var currentBabyIDRaw = ""
    /// The accessory strip has a height the system fixes, and large text can't
    /// grow it, so at accessibility sizes the bar says less rather than
    /// truncating everything into ellipses.
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    private var unit: VolumeUnit { VolumeUnit(rawValue: unitRaw) ?? .ounces }
    private var lastFeed: FeedEntry? { entries.active(for: UUID(uuidString: currentBabyIDRaw)).first }

    var body: some View {
        Button {
            router.openLog(kind: lastFeed?.kind)
        } label: {
            HStack(spacing: 10) {
                if let last = lastFeed {
                    Image(systemName: last.kind.systemImage)
                        .foregroundStyle(last.kind.color)
                    if dynamicTypeSize.isAccessibilitySize {
                        elapsedOnly(last)
                    } else {
                        fullDetail(last)
                    }
                } else {
                    Image(systemName: "moon.zzz.fill")
                        .foregroundStyle(.secondary)
                    Text(dynamicTypeSize.isAccessibilitySize ? "First feed" : "Log the first feed")
                        .font(.subheadline)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
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
        .accessibilityLabel(accessibilityLabel)
    }

    /// Nothing but the elapsed time. "Last fed … ago" and the due line can't
    /// fit at these sizes, and a row of ellipses tells you less than the one
    /// number you opened the app for.
    private func elapsedOnly(_ last: FeedEntry) -> some View {
        TimelineView(.periodic(from: .now, by: 60)) { context in
            Text(ElapsedText.compact(since: last.startTime, now: context.date))
                .font(.subheadline.weight(.semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
    }

    private func fullDetail(_ last: FeedEntry) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 4) {
                Text("Last fed")
                Text(last.startTime, style: .relative)
                    .fontWeight(.semibold)
                Text("ago")
            }
            .font(.subheadline)
            .lineLimit(1)
            .minimumScaleFactor(0.8)
            if remindersEnabled {
                let due = last.startTime.addingTimeInterval(Double(AppSettings.resolvedIntervalMinutes(raw: intervalMinutesRaw)) * 60)
                Text(due > .now ? "Next around \(due, format: .dateTime.hour().minute())" : "Feed is due")
                    .font(.caption)
                    .foregroundStyle(due > .now ? Color.secondary : Color.orange)
                    .lineLimit(1)
            } else {
                Text("\(last.kind.title) · \(last.detailText(unit: unit))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
    }

    /// The visible text shrinks at accessibility sizes, so VoiceOver has to
    /// carry what was dropped – otherwise the bar reads as just "Log a feed"
    /// and the time since the last feed is lost.
    private var accessibilityLabel: String {
        guard let last = lastFeed else { return "Log the first feed" }
        return "Last fed \(ElapsedText.compact(since: last.startTime)) ago. Log a feed."
    }
}
