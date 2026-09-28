import LocalAuthentication
import SwiftUI
import UIKit
import UniformTypeIdentifiers

/// "Your recovery phrase": the one phrase that brings back every log you're
/// on, hidden until you ask for it.
///
/// Hidden rather than shown, for the same reason a wallet hides a seed phrase:
/// the risk isn't forgetting what it looks like, it's that it ends up in a
/// screenshot or over somebody's shoulder. Face ID to reveal, and it's covered
/// again the moment the app goes away.
///
/// The phone holds the phrase; the server only has a hash, so it can be looked
/// at here as often as needed. Replacing it is always a deliberate step: a
/// phone that merely lacks a copy never quietly retires the one on paper.
struct RecoveryKeyView: View {
    let babyName: String

    @Environment(\.scenePhase) private var scenePhase
    @State private var sync = SyncEngine.shared
    @State private var phrase: String?
    @State private var isRevealed = false
    @State private var isWorking = false
    @State private var errorMessage: String?
    @State private var showReplaceConfirm = false

    var body: some View {
        List {
            Section {
                panel
                    .listRowInsets(EdgeInsets(top: 16, leading: 16, bottom: 16, trailing: 16))
            } footer: {
                if let status = statusText { Text(status) }
            }

            if isRevealed, let phrase {
                Section {
                    Button {
                        UIPasteboard.general.setItems(
                            [[UTType.utf8PlainText.identifier: RecoveryKey.formatted(phrase)]],
                            options: [.localOnly: true, .expirationDate: Date.now.addingTimeInterval(120)]
                        )
                    } label: {
                        Label("Copy for 2 minutes", systemImage: "doc.on.doc")
                    }
                    ShareLink(item: PhraseFile(phrase: phrase, babyName: babyName),
                              preview: SharePreview("Baby Feed recovery phrase")) {
                        Label("Save to Files or share", systemImage: "square.and.arrow.up")
                    }
                    if !RecoveryPhraseReminder.confirmed {
                        Button {
                            RecoveryPhraseReminder.confirmed = true
                        } label: {
                            Label("I've written it down", systemImage: "checkmark")
                        }
                    }
                }
            }

            Section {
                Label {
                    Text("It brings back every log you're on if every phone that has them is gone. Nobody can reissue it: not the server, not us.")
                } icon: {
                    Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
                }
                .font(.footnote)
                Label {
                    Text("Anyone with these characters can open the log, the same as a house key.")
                } icon: {
                    Image(systemName: "eye.trianglebadge.exclamationmark").foregroundStyle(.orange)
                }
                .font(.footnote)
            } header: {
                Text("What it is")
            }

            actions

            if let errorMessage {
                Section { Text(errorMessage).font(.footnote).foregroundStyle(.red) }
            }
        }
        .navigationTitle("Your recovery phrase")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            phrase = sync.recoveryPhrase
            await sync.refreshPhraseState()
        }
        // Cover it again the moment the app goes away, so it isn't sitting
        // revealed in the app switcher.
        .onChange(of: scenePhase) { _, phase in
            if phase != .active { isRevealed = false }
        }
        .confirmationDialog("Replace your recovery phrase?", isPresented: $showReplaceConfirm, titleVisibility: .visible) {
            Button("Make a new phrase", role: .destructive) { Task { await replace() } }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("The old phrase stops working straight away. Anything written down with it becomes useless.")
        }
    }

    // MARK: Pieces

    @ViewBuilder
    private var panel: some View {
        if isWorking {
            HStack { Spacer(); ProgressView(); Spacer() }.frame(height: 96)
        } else if phrase == nil {
            VStack(spacing: 6) {
                Image(systemName: "key.slash").font(.title2).foregroundStyle(.secondary)
                Text(sync.phraseState == .notOnThisPhone
                     ? "Your phrase was made on another phone"
                     : "No recovery phrase yet")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
        } else if isRevealed, let phrase {
            PhraseText(phrase: phrase)
        } else {
            Button {
                Task { await reveal() }
            } label: {
                VStack(spacing: 8) {
                    Image(systemName: "eye.slash.fill").font(.title2)
                    Text("Tap to reveal").font(.subheadline.weight(.medium))
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 20)
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
        }
    }

    private var statusText: String? {
        switch sync.phraseState {
        case .matches: "Your Mac mini has this phrase. It covers \(babyName)'s log."
        case .differs: "A different phrase was set up on another phone since. The one here no longer works."
        case .notRegistered: "Not registered with your Mac mini yet. It will be the next time this phone syncs at home."
        case .notOnThisPhone: "If you have it written down, you're covered. If not, make a new one below."
        case .unknown: SyncCredentials.isPaired ? nil : "Registered when this phone first backs up to your Mac mini."
        }
    }

    @ViewBuilder
    private var actions: some View {
        if SyncCredentials.isPaired {
            Section {
                if phrase == nil && sync.phraseState != .notOnThisPhone {
                    Button("Make my recovery phrase") { Task { await register() } }
                        .disabled(isWorking)
                } else {
                    Button(sync.phraseState == .differs ? "Use a new phrase from this phone" : "Replace my recovery phrase",
                           role: .destructive) { showReplaceConfirm = true }
                        .disabled(isWorking)
                }
            } footer: {
                Text(phrase == nil
                     ? "It's made on this phone and only its fingerprint goes to your Mac mini."
                     : "Makes a new phrase and retires the old one immediately. Worth doing if you've lost track of where the old one was written.")
            }
        }
    }

    // MARK: Actions

    private func register() async {
        isWorking = true
        errorMessage = nil
        defer { isWorking = false }
        do {
            phrase = try await sync.registerPhrase()
            RecoveryPhraseReminder.confirmed = false
            isRevealed = true
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }

    private func replace() async {
        isWorking = true
        errorMessage = nil
        defer { isWorking = false }
        do {
            phrase = try await sync.replacePhrase()
            RecoveryPhraseReminder.confirmed = false
            isRevealed = true
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }

    private func reveal() async {
        let context = LAContext()
        context.localizedCancelTitle = "Cancel"
        var error: NSError?
        // If the phone has no passcode at all there's nothing to check against,
        // and refusing to show it would just make the phrase unreachable.
        guard context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &error) else {
            isRevealed = true
            return
        }
        do {
            isRevealed = try await context.evaluatePolicy(
                .deviceOwnerAuthentication,
                localizedReason: "Show your Baby Feed recovery phrase")
        } catch {
            // Cancelling is an answer, not a failure worth a red line.
            isRevealed = false
        }
    }
}

#Preview {
    NavigationStack {
        RecoveryKeyView(babyName: "Nora")
    }
}
