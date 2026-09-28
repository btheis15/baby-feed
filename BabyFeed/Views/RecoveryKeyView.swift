import LocalAuthentication
import SwiftUI

/// The recovery key for one baby's log, hidden until you ask for it.
///
/// Hidden rather than shown, for the same reason a wallet hides a seed phrase:
/// the risk isn't that you forget what it looks like, it's that it ends up in
/// a screenshot or over somebody's shoulder. Face ID to reveal, and the app
/// covers it again when you leave.
///
/// It can be looked at as often as you like. The phone holds the key; the
/// server only has a hash, so nothing here is a one-time showing that has to
/// be got right first go at 3 a.m.
struct RecoveryKeyView: View {
    let babyID: UUID
    let babyName: String

    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase

    @State private var key: String?
    @State private var isRevealed = false
    @State private var isWorking = true
    @State private var errorMessage: String?
    @State private var showReplaceConfirm = false

    private var formatted: String { key.map(RecoveryKey.formatted) ?? "" }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    keyPanel
                        .listRowInsets(EdgeInsets(top: 16, leading: 16, bottom: 16, trailing: 16))
                } footer: {
                    Text("Write it down and keep it somewhere you'd keep a passport. It's also saved in your iCloud Keychain, so a restored iPhone usually already has it — but paper is the part that doesn't depend on anything.")
                }

                if isRevealed, let key {
                    Section {
                        Button {
                            UIPasteboard.general.string = RecoveryKey.formatted(key)
                        } label: {
                            Label("Copy", systemImage: "doc.on.doc")
                        }
                        ShareLink(item: RecoveryKey.formatted(key)) {
                            Label("Save somewhere else", systemImage: "square.and.arrow.up")
                        }
                    }
                }

                Section {
                    Label {
                        Text("This is the only way back to \(babyName)'s log if every phone that has it is gone. Nobody can reissue it for you — not the server, not me.")
                    } icon: {
                        Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
                    }
                    .font(.footnote)

                    Label {
                        Text("Anyone who has these characters can read and change the log, the same as a house key.")
                    } icon: {
                        Image(systemName: "eye.trianglebadge.exclamationmark").foregroundStyle(.orange)
                    }
                    .font(.footnote)
                } header: {
                    Text("What it is")
                }

                if key != nil {
                    Section {
                        Button("Replace this key", role: .destructive) { showReplaceConfirm = true }
                    } footer: {
                        Text("Makes a new one and retires the old immediately. Worth doing if you've lost track of where the old one was written.")
                    }
                }

                if let errorMessage {
                    Section { Text(errorMessage).font(.footnote).foregroundStyle(.red) }
                }
            }
            .navigationTitle("Recovery key")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            }
            .task { await load() }
            // Cover it again the moment the app goes away, so it isn't sitting
            // revealed in the app switcher.
            .onChange(of: scenePhase) { _, phase in
                if phase != .active { isRevealed = false }
            }
            .confirmationDialog("Replace the recovery key?", isPresented: $showReplaceConfirm, titleVisibility: .visible) {
                Button("Replace it", role: .destructive) { Task { await replace() } }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("The old key stops working straight away. Anything written down with it becomes useless.")
            }
        }
    }

    @ViewBuilder
    private var keyPanel: some View {
        if isWorking {
            HStack { Spacer(); ProgressView(); Spacer() }.frame(height: 96)
        } else if key == nil {
            HStack { Spacer(); Text("No key yet").foregroundStyle(.secondary); Spacer() }.frame(height: 96)
        } else if isRevealed {
            Text(formatted)
                .font(.system(.title3, design: .monospaced).weight(.semibold))
                .multilineTextAlignment(.center)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .accessibilityLabel(spelledOut)
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

    /// Read out one character at a time; VoiceOver would otherwise make words
    /// of it, which is no use to someone copying it down.
    private var spelledOut: String {
        formatted.map { $0 == "-" ? "," : String($0) }.joined(separator: " ")
    }

    private func load() async {
        isWorking = true
        defer { isWorking = false }
        do {
            key = try await SyncEngine.shared.recoveryKey(for: babyID)
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }

    private func replace() async {
        isWorking = true
        errorMessage = nil
        defer { isWorking = false }
        do {
            key = try await SyncEngine.shared.replaceRecoveryKey(for: babyID)
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
        // and refusing to show it would just make the key unreachable.
        guard context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &error) else {
            isRevealed = true
            return
        }
        do {
            isRevealed = try await context.evaluatePolicy(
                .deviceOwnerAuthentication,
                localizedReason: "Show the recovery key for \(babyName)'s log")
        } catch {
            // Cancelling is an answer, not a failure worth a red line.
            isRevealed = false
        }
    }
}
