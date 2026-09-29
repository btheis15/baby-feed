import SwiftUI

/// Today's hero while a nursing timer runs: "NURSING · LEFT · 12 min", with
/// the switch, Done and Cancel under a thumb. Minutes only, like everything
/// else; it sits in Today's once-a-minute TimelineView.
struct NursingHero: View {
    let session: NursingSession
    let now: Date
    let timeZone: TimeZone
    let onSwitch: () -> Void
    let onDone: () -> Void
    let onCancel: () -> Void

    var body: some View {
        VStack(spacing: 10) {
            Text("Nursing · \(session.side.title)")
                .font(.subheadline.weight(.medium))
                .foregroundStyle(FeedKind.nursing.color)
                .textCase(.uppercase)

            Text(ElapsedText.compact(minutes: session.minutes(at: now)))
                .font(.system(size: 64, weight: .bold, design: .rounded))
                .monospacedDigit()
                .contentTransition(.numericText())

            Text(detail)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            if session.isProbablyForgotten(at: now) {
                Label("Still nursing? Tap Done when you're finished.", systemImage: "questionmark.circle")
                    .font(.footnote.weight(.medium))
                    .foregroundStyle(.orange)
            }

            HStack(spacing: 12) {
                Button(action: onSwitch) {
                    // Words only: with the arrows icon, "Switch side" either
                    // broke onto two lines, taller than Done, or cut off.
                    Text("Switch side")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
                .accessibilityLabel("Switch to the \(session.side == .left ? "right" : "left") side")
                .buttonStyle(.bordered)
                .controlSize(.large)
                .tint(FeedKind.nursing.color)

                Button(action: onDone) {
                    Text("Done").frame(maxWidth: .infinity, maxHeight: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .tint(FeedKind.nursing.color)
            }
            // Both buttons as tall as the taller one, even at large text sizes.
            .fixedSize(horizontal: false, vertical: true)
            .padding(.top, 4)

            Button("Cancel timer", role: .destructive, action: onCancel)
                .font(.footnote)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 16)
        .accessibilityElement(children: .contain)
    }

    /// "Started 2:10 PM · 4 min on this side", or "just switched" in the first
    /// minute, which used to read "0 min" beside a total that never shows less
    /// than one.
    private var detail: String {
        var parts = ["Started \(ClockText.time(session.startedAt, in: timeZone))"]
        if !session.switches.isEmpty {
            let onSide = session.minutesOnCurrentSide(at: now)
            parts.append(onSide < 1 ? "just switched" : "\(onSide) min on this side")
        }
        return parts.joined(separator: " · ")
    }
}
