import SwiftUI

/// What a scanned QR (or a sent link) opens: it joins straight away, says so,
/// and asks what to call you if the phone doesn't know yet.
///
/// Scanning the other phone's code is itself the handoff: it's phone to phone,
/// it carries the address and a short-lived code, and it can't happen by
/// accident. So there's nothing here to fill in before it connects.
struct JoinView: View {
    let invitation: SyncLink.Invitation

    @Environment(\.dismiss) private var dismiss

    private enum Phase: Equatable {
        case joining
        case joined(babyName: String?, askName: Bool)
        case failed(title: String, detail: String, canRetry: Bool)
    }

    @State private var phase: Phase = .joining
    @State private var name = ""
    /// So a redraw can't start a second join for the same code.
    @State private var started = false

    private static let nameChoices = ["Mom", "Dad", "Grandma", "Grandpa", "Nanny"]

    var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
                Spacer()
                switch phase {
                case .joining:
                    ProgressView()
                        .controlSize(.large)
                    Text("Joining the log…")
                        .font(.title3.weight(.semibold))
                case .joined(let babyName, let askName):
                    joined(babyName: babyName, askName: askName)
                case .failed(let title, let detail, let canRetry):
                    failed(title: title, detail: detail, canRetry: canRetry)
                }
                Spacer()
            }
            .padding(.horizontal, 24)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    if phase != .joining {
                        Button("Close") { dismiss() }
                    }
                }
            }
        }
        .interactiveDismissDisabled(phase == .joining)
        .task {
            guard !started else { return }
            started = true
            await join()
        }
    }

    // MARK: States

    @ViewBuilder
    private func joined(babyName: String?, askName: Bool) -> some View {
        Image(systemName: "checkmark.circle.fill")
            .font(.system(size: 56))
            .foregroundStyle(.green)
            .accessibilityHidden(true)
        Text("You're in")
            .font(.largeTitle.bold())
        Text(babyName.map { "\($0)'s log is on this phone." } ?? "The log is on this phone.")
            .font(.headline)
            .foregroundStyle(.secondary)
            .multilineTextAlignment(.center)

        if askName {
            VStack(alignment: .leading, spacing: 12) {
                Text("What should we call you?")
                    .font(.headline)
                NameChips(choices: Self.nameChoices, name: $name)
                TextField("Or type a name", text: $name)
                    .textInputAutocapitalization(.words)
                    .textFieldStyle(.roundedBorder)
                Text("Shown next to everything you log, so the other phone can tell your entries from theirs.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            .padding(.top, 12)

            HStack(spacing: 12) {
                Button("Skip") { dismiss() }
                    .controlSize(.large)
                Button {
                    Task {
                        await SyncEngine.shared.updateDisplayName(name.trimmingCharacters(in: .whitespacesAndNewlines))
                        dismiss()
                    }
                } label: {
                    Text("Done").frame(maxWidth: .infinity)
                }
                .buttonStyle(.glassProminent)
                .controlSize(.large)
                .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            .padding(.top, 8)
        } else {
            Button {
                dismiss()
            } label: {
                Text("Done").frame(maxWidth: .infinity)
            }
            .buttonStyle(.glassProminent)
            .controlSize(.large)
            .padding(.top, 12)
        }
    }

    @ViewBuilder
    private func failed(title: String, detail: String, canRetry: Bool) -> some View {
        Image(systemName: "exclamationmark.triangle")
            .font(.system(size: 48))
            .foregroundStyle(.orange)
            .accessibilityHidden(true)
        Text(title)
            .font(.title3.bold())
            .multilineTextAlignment(.center)
        Text(detail)
            .font(.subheadline)
            .foregroundStyle(.secondary)
            .multilineTextAlignment(.center)
        if canRetry {
            Button("Try again") {
                Task { await join() }
            }
            .buttonStyle(.bordered)
            .controlSize(.large)
        }
    }

    // MARK: Joining

    private func join() async {
        phase = .joining
        do {
            let joined = try await SyncEngine.shared.join(invitation)
            withAnimation {
                phase = .joined(babyName: joined.babyName, askName: joined.needsName)
            }
        } catch let error as SyncError {
            phase = Self.failure(for: error)
        } catch {
            phase = .failed(title: "Couldn't join", detail: error.localizedDescription, canRetry: true)
        }
    }

    /// Plain words for what went wrong, and whether trying again could help.
    private static func failure(for error: SyncError) -> Phase {
        switch error {
        case .away:
            .failed(title: "Can't reach the other phone's Mac mini",
                    detail: "Connect to the same Wi‑Fi as the other phone, then try again.",
                    canRetry: true)
        case .serverNeedsUpdate:
            .failed(title: "The server needs an update",
                    detail: "The Baby Feed server on the Mac mini is older than this app. Update it, then scan again.",
                    canRetry: false)
        case .server(_, _, let code) where code == "expired_code" || code == "used_code":
            .failed(title: "That code has expired",
                    detail: "Ask them to tap Share again and scan the new code.",
                    canRetry: false)
        case .server(_, _, let code) where code == "bad_code":
            .failed(title: "That code isn't valid",
                    detail: "Ask them to tap Share again and scan the new code.",
                    canRetry: false)
        case .server(_, _, let code) where code == "baby_gone":
            .failed(title: "That log is gone",
                    detail: "It was deleted on the other phone.",
                    canRetry: false)
        default:
            .failed(title: "Couldn't join", detail: error.errorDescription ?? "Something went wrong.", canRetry: true)
        }
    }
}

#Preview {
    JoinView(invitation: SyncLink.Invitation(code: "ABC123", server: URL(string: "http://mini.local:8791")!))
}
