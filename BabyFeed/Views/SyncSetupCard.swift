import SwiftData
import SwiftUI

/// At most one card on Today about keeping the log safe, and only while
/// there's something to do:
///
/// - **Back up**, for a phone from before sharing: "Back up Nora to your Mac
///   mini · you'll also get a recovery phrase".
/// - **Write down your recovery phrase**, after "Remind me later".
///
/// Either can be put off; neither comes back sooner than three days.
struct SyncSetupCard: View {
    let babyName: String
    let hasRealBaby: Bool

    @Environment(AppRouter.self) private var router
    @State private var sync = SyncEngine.shared
    @State private var isWorking = false
    @State private var message: String?
    @AppStorage("sync.setupCardSnoozedUntil") private var snoozedUntil: Double = 0

    private enum Kind { case backUp, phrase }

    private var kind: Kind? {
        // Keep saying what happened after "Back up now" until it's put away.
        if message != nil { return .backUp }
        guard Date.now.timeIntervalSince1970 >= snoozedUntil else { return nil }
        if !sync.isConfigured, sync.hasServer, hasRealBaby,
           !SyncCredentials.connectionRequested, !SyncCredentials.optedOut {
            return .backUp
        }
        if sync.isConfigured, sync.recoveryPhrase != nil, !RecoveryPhraseReminder.confirmed {
            return .phrase
        }
        return nil
    }

    var body: some View {
        if let kind {
            Section {
                VStack(alignment: .leading, spacing: 10) {
                    Label {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(kind == .backUp ? "Back up \(babyName) to your Mac mini" : "Write down your recovery phrase")
                                .font(.headline)
                            Text(kind == .backUp
                                 ? "So the log is safe if this phone isn't, and another phone can share it. You'll also get a recovery phrase."
                                 : "It brings \(babyName)'s log back if this phone is ever lost.")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                    } icon: {
                        Image(systemName: kind == .backUp ? "arrow.up.to.line.circle.fill" : "key.fill")
                            .font(.title2)
                            .foregroundStyle(.tint)
                    }

                    if let message {
                        Text(message).font(.footnote).foregroundStyle(.secondary)
                    }

                    HStack(spacing: 12) {
                        Button {
                            act(kind)
                        } label: {
                            Group {
                                if isWorking { ProgressView() } else { Text(kind == .backUp ? "Back up now" : "Show it") }
                            }
                            .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(isWorking)

                        Button(message == nil ? "Later" : "OK") {
                            snoozedUntil = Date.now.addingTimeInterval(3 * 24 * 3600).timeIntervalSince1970
                            message = nil
                        }
                        .buttonStyle(.bordered)
                    }
                }
                .padding(.vertical, 4)
            }
        }
    }

    private func act(_ kind: Kind) {
        switch kind {
        case .phrase:
            router.sheet = .recoverySetup
        case .backUp:
            isWorking = true
            message = nil
            Task {
                do {
                    SyncEngine.shared.preparePhrase()
                    try await sync.ensureConnected(.backUp)
                    router.sheet = .recoverySetup
                } catch SyncError.away {
                    message = SyncEngine.syncsAwayFromHome
                        ? "Can't reach your Mac mini right now. It'll back up by itself once it can."
                        : "Can't reach your Mac mini from here. It'll back up by itself once this phone is on your home Wi‑Fi."
                } catch {
                    message = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
                }
                isWorking = false
            }
        }
    }
}
