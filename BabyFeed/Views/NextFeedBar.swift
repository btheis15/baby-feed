import SwiftData
import SwiftUI

/// Content of the tab bar accessory: always-visible "next feed in … / last fed".
///
/// Visible on every tab, so it's the one place a seconds-ticking clock would
/// cost the most. It changes once a minute, like the hero.
struct NextFeedBar: View {
    @Environment(AppRouter.self) private var router
    @Environment(\.timeZone) private var timeZone
    @Query(sort: \FeedEntry.startTime, order: .reverse) private var entries: [FeedEntry]
    /// 0 means "follow what's typical for this age"; resolved by AppSettings.
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
        TimelineView(.everyMinute) { context in
            let countdown = AppSettings.countdown(
                lastFeed: lastFeed?.startTime,
                intervalRaw: intervalMinutesRaw,
                now: context.date
            )
            Button {
                router.openLog(kind: lastFeed?.kind)
            } label: {
                HStack(spacing: 10) {
                    Image(systemName: lastFeed?.kind.systemImage ?? "moon.zzz.fill")
                        .foregroundStyle(lastFeed?.kind.color ?? .secondary)
                    VStack(alignment: .leading, spacing: 0) {
                        Text(headline(countdown, now: context.date))
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(countdown.isOverdue ? Color.red : Color.primary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                        if !dynamicTypeSize.isAccessibilitySize, let detail = detail(countdown, now: context.date) {
                            Text(detail)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
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
            .accessibilityLabel(accessibilityLabel(countdown, now: context.date))
        }
    }

    private func headline(_ countdown: FeedCountdown, now: Date) -> String {
        let compact = dynamicTypeSize.isAccessibilitySize
        switch countdown {
        case .noFeeds:
            return compact ? "First feed" : "Log the first feed"
        case .upcoming(_, let minutesLeft):
            let left = ElapsedText.compact(minutes: minutesLeft)
            return compact ? left : "Next feed in \(left)"
        case .overdue(_, let minutesLate):
            if minutesLate == 0 { return "Feed is due" }
            let late = ElapsedText.compact(minutes: minutesLate)
            return compact ? "Due · \(late)" : "Feed due · \(late) late"
        case .quiet(let lastFeedTime):
            return "Last fed \(ClockText.since(lastFeedTime, now: now, in: timeZone))"
        }
    }

    private func detail(_ countdown: FeedCountdown, now: Date) -> String? {
        guard let lastFeed else { return nil }
        let last = "last fed \(ClockText.time(lastFeed.startTime, in: timeZone))"
        switch countdown {
        case .noFeeds:
            return nil
        case .upcoming(let due, _):
            return "around \(ClockText.time(due, in: timeZone)) · \(last)"
        case .overdue(let due, _):
            return "was due \(ClockText.time(due, in: timeZone)) · \(last)"
        case .quiet:
            return "\(lastFeed.kind.title) · \(lastFeed.detailText(unit: unit))"
        }
    }

    /// The visible text shrinks at accessibility sizes, so VoiceOver carries
    /// what was dropped.
    private func accessibilityLabel(_ countdown: FeedCountdown, now: Date) -> String {
        switch countdown {
        case .noFeeds:
            return "Log the first feed"
        case .upcoming(let due, let minutesLeft):
            return "Next feed in \(ElapsedText.spoken(minutes: minutesLeft)), around \(ClockText.time(due, in: timeZone)). Log a feed."
        case .overdue(let due, let minutesLate):
            return minutesLate == 0
                ? "The next feed is due now. Log a feed."
                : "Feed \(ElapsedText.spoken(minutes: minutesLate)) overdue, it was due at \(ClockText.time(due, in: timeZone)). Log a feed."
        case .quiet(let lastFeedTime):
            return "Last fed \(ClockText.since(lastFeedTime, now: now, in: timeZone)). Log a feed."
        }
    }
}
