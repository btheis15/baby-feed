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
                    Label("Switch side", systemImage: "arrow.left.arrow.right")
                        .frame(maxWidth: .infinity)
                }
                .accessibilityLabel("Switch to the \(session.side == .left ? "right" : "left") side")
                .buttonStyle(.bordered)
                .controlSize(.large)
                .tint(FeedKind.nursing.color)

                Button(action: onDone) {
                    Text("Done").frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .tint(FeedKind.nursing.color)
            }
            .padding(.top, 4)

            Button("Cancel timer", role: .destructive, action: onCancel)
                .font(.footnote)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 16)
        .accessibilityElement(children: .contain)
    }

    /// "Started 2:10 PM · 4 min on this side"
    private var detail: String {
        var parts = ["Started \(ClockText.time(session.startedAt, in: timeZone))"]
        if !session.switches.isEmpty {
            parts.append("\(session.minutesOnCurrentSide(at: now)) min on this side")
        }
        return parts.joined(separator: " · ")
    }
}
