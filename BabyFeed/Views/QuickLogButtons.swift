import SwiftUI

/// The three feed buttons, in one row. Each shows the amount it will pre-fill,
/// so the common case is tap, then Save.
struct QuickLogButtons: View {
    let unit: VolumeUnit
    /// The side to start nursing on, when last time says which.
    var nursingSide: NursingSide? = nil
    let onTap: (FeedKind) -> Void

    /// Pinned amounts, 0 when following the recommendation.
    @AppStorage(FeedDefaults.amountKey(for: .formula)) private var formulaML: Double = 0
    @AppStorage(FeedDefaults.amountKey(for: .breastMilk)) private var breastMilkML: Double = 0
    /// Read so the buttons re-render when the guidance moves.
    @AppStorage(FeedDefaults.recommendedPerFeedKey) private var recommendedML: Double = 0
    @AppStorage(FeedDefaults.lastNursingMinutes) private var nursingMinutes: Int = 0
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        // Three across stops fitting at the accessibility sizes, where
        // "Breast Milk" would break mid-word; there they stack as wide rows.
        if dynamicTypeSize.isAccessibilitySize {
            VStack(spacing: 10) {
                ForEach(FeedKind.allCases) { kind in
                    wideButton(kind)
                }
            }
        } else {
            HStack(spacing: 10) {
                ForEach(FeedKind.allCases) { kind in
                    tile(kind)
                }
            }
        }
    }

    private func subtitle(for kind: FeedKind) -> String {
        guard kind.usesVolume else {
            if let nursingSide { return "start \(nursingSide.title)" }
            return "\(nursingMinutes > 0 ? nursingMinutes : 15) min"
        }
        return unit.format(milliliters: FeedDefaults.defaultAmountML(for: kind, unit: unit))
    }

    private func tile(_ kind: FeedKind) -> some View {
        Button {
            onTap(kind)
        } label: {
            VStack(spacing: 4) {
                Image(systemName: kind.systemImage)
                    .font(.system(size: 24))
                Text(kind.title)
                    .font(.subheadline.weight(.semibold))
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .minimumScaleFactor(0.85)
                Text(subtitle(for: kind))
                    .font(.footnote)
                    .monospacedDigit()
                    .opacity(0.75)
            }
            .padding(.vertical, 12)
            .padding(.horizontal, 4)
            .frame(maxWidth: .infinity, minHeight: 96)
            .background(kind.color.opacity(0.15), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .foregroundStyle(kind.color)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Log \(kind.title), \(subtitle(for: kind))")
    }

    private func wideButton(_ kind: FeedKind) -> some View {
        Button {
            onTap(kind)
        } label: {
            HStack(spacing: 12) {
                Image(systemName: kind.systemImage)
                    .font(.title2)
                VStack(alignment: .leading, spacing: 2) {
                    Text(kind.title)
                        .font(.headline)
                    Text(subtitle(for: kind))
                        .font(.subheadline)
                        .opacity(0.75)
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity, minHeight: 72)
            .background(kind.color.opacity(0.15), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
            .foregroundStyle(kind.color)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Log \(kind.title), \(subtitle(for: kind))")
    }
}

#Preview {
    QuickLogButtons(unit: .ounces, nursingSide: .right) { _ in }
        .padding()
}
