import SwiftUI

/// The three big buttons. Each shows the amount it will pre-fill.
struct QuickLogButtons: View {
    let unit: VolumeUnit
    let onTap: (FeedKind) -> Void

    /// Pinned amounts, 0 when following the recommendation.
    @AppStorage(FeedDefaults.amountKey(for: .formula)) private var formulaML: Double = 0
    @AppStorage(FeedDefaults.amountKey(for: .breastMilk)) private var breastMilkML: Double = 0
    /// Read so the buttons re-render when the guidance moves.
    @AppStorage(FeedDefaults.recommendedPerFeedKey) private var recommendedML: Double = 0
    @AppStorage(FeedDefaults.lastNursingMinutes) private var nursingMinutes: Int = 0

    var body: some View {
        VStack(spacing: 12) {
            HStack(spacing: 12) {
                bigButton(.formula, subtitle: amountText(for: .formula))
                bigButton(.breastMilk, subtitle: amountText(for: .breastMilk))
            }
            wideButton(.nursing, subtitle: "\(nursingMinutes > 0 ? nursingMinutes : 15) min")
        }
    }

    private func amountText(for kind: FeedKind) -> String {
        unit.format(milliliters: FeedDefaults.defaultAmountML(for: kind, unit: unit))
    }

    private func bigButton(_ kind: FeedKind, subtitle: String) -> some View {
        Button {
            onTap(kind)
        } label: {
            VStack(spacing: 6) {
                Image(systemName: kind.systemImage)
                    .font(.system(size: 30))
                Text(kind.title)
                    .font(.headline)
                Text(subtitle)
                    .font(.subheadline)
                    .opacity(0.75)
            }
            .frame(maxWidth: .infinity, minHeight: 120)
            .background(kind.color.opacity(0.15), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
            .foregroundStyle(kind.color)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Log \(kind.title), \(subtitle)")
    }

    private func wideButton(_ kind: FeedKind, subtitle: String) -> some View {
        Button {
            onTap(kind)
        } label: {
            HStack(spacing: 12) {
                Image(systemName: kind.systemImage)
                    .font(.system(size: 26))
                Text(kind.title)
                    .font(.headline)
                Spacer()
                Text(subtitle)
                    .font(.subheadline)
                    .opacity(0.75)
            }
            .padding(.horizontal, 20)
            .frame(maxWidth: .infinity, minHeight: 72)
            .background(kind.color.opacity(0.15), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
            .foregroundStyle(kind.color)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Log \(kind.title), \(subtitle)")
    }
}
