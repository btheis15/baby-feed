import SwiftUI

/// Shown once, on the first launch, and never again.
///
/// It exists for one reason: the log lives on this iPhone, and until you've
/// either shared it or signed in, losing the phone loses the log. That is not
/// a thing to find out afterwards. But it is also not a thing to make a parent
/// deal with before they can write down a feed at 4 a.m., so this is a card
/// with a plain way out, not a wall — "Not now" is a real answer and the app
/// behaves identically either way.
struct SharingIntroView: View {
    @Environment(\.dismiss) private var dismiss
    /// Set by the caller when someone takes the offer, so Today can open the
    /// pairing sheet after this one has gone.
    @Binding var wantsToSetUpSharing: Bool

    var body: some View {
        VStack(spacing: 0) {
            Spacer(minLength: 24)

            Image(systemName: "iphone.and.arrow.forward.inward")
                .font(.system(size: 52))
                .foregroundStyle(.tint)
                .padding(.bottom, 20)
                .accessibilityHidden(true)

            Text("Keep the log safe")
                .font(.title.bold())
                .multilineTextAlignment(.center)

            Text("Everything you log stays on this iPhone and works with no signal. Sharing adds a copy on a small server at your house — so the other caregiver sees the same feeds, and so your log comes back if this phone doesn't.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 28)
                .padding(.top, 10)

            Spacer(minLength: 20)

            VStack(alignment: .leading, spacing: 18) {
                point("person.2.fill", "Both phones, one log",
                      "Feeds, weights and notes show up on the other caregiver's phone, with who logged what.")
                point("lock.iphone", "No account to make",
                      "No email, no password, nothing to sign up for. It syncs through a server you run yourself, and a recovery key you can write down is the way back if every phone is lost.")
            }
            .padding(.horizontal, 32)

            Spacer(minLength: 24)

            VStack(spacing: 12) {
                Button {
                    // No dismiss: the caller swaps this sheet for the pairing
                    // one, so there's no gap where nothing is on screen.
                    wantsToSetUpSharing = true
                } label: {
                    Text("Set up sharing").frame(maxWidth: .infinity)
                }
                .buttonStyle(.glassProminent)
                .controlSize(.large)

                Button("Not now") { dismiss() }
                    .controlSize(.large)

                Text("You can do this any time under Settings › Caregivers & sync.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 12)
        }
        .interactiveDismissDisabled(false)
    }

    private func point(_ symbol: String, _ title: String, _ detail: String) -> some View {
        Label {
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.subheadline.weight(.semibold))
                Text(detail).font(.footnote).foregroundStyle(.secondary)
            }
        } icon: {
            Image(systemName: symbol).foregroundStyle(.tint).frame(width: 26)
        }
    }
}

#Preview {
    SharingIntroView(wantsToSetUpSharing: .constant(false))
}
