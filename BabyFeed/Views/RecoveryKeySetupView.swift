import SwiftUI
import UIKit
import UniformTypeIdentifiers

/// "Your recovery phrase", shown once, right after the baby is added: the way
/// back to the log if this phone is ever lost. Shown without Face ID this one
/// time, because it was made a moment ago and nobody else has seen it.
///
/// One phrase per parent, covering every log they're on, so this is the only
/// time most people ever see it.
struct RecoveryKeySetupView: View {
    let phrase: String
    let babyName: String
    let onDone: () -> Void

    @State private var copied = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    VStack(spacing: 10) {
                        Image(systemName: "key.fill")
                            .font(.system(size: 40))
                            .foregroundStyle(.tint)
                            .accessibilityHidden(true)
                        Text("Your recovery phrase")
                            .font(.title2.bold())
                        Text("If you ever lose your phone, this brings back \(babyName)'s log. Nobody can reissue it, so keep it somewhere safe.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                    }

                    PhraseText(phrase: phrase)

                    VStack(spacing: 12) {
                        Button {
                            copy()
                        } label: {
                            Label(copied ? "Copied for 2 minutes" : "Copy", systemImage: copied ? "checkmark" : "doc.on.doc")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.large)

                        ShareLink(item: PhraseFile(phrase: phrase, babyName: babyName),
                                  preview: SharePreview("Baby Feed recovery phrase")) {
                            Label("Save to Files or share", systemImage: "square.and.arrow.up")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.large)
                    }

                    Text("It's also kept in your iCloud Keychain, but paper is the copy that doesn't depend on anything.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                .padding(24)
            }
            .safeAreaInset(edge: .bottom) {
                VStack(spacing: 8) {
                    Button {
                        RecoveryPhraseReminder.confirmed = true
                        onDone()
                    } label: {
                        Text("I've written it down")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.glassProminent)
                    .controlSize(.large)

                    Button("Remind me later") {
                        RecoveryPhraseReminder.confirmed = false
                        onDone()
                    }
                    .controlSize(.large)
                }
                .padding(.horizontal, 24)
                .padding(.vertical, 12)
                .background(.bar)
            }
            .interactiveDismissDisabled()
        }
    }

    /// On this device's clipboard only, and only for two minutes: a phrase
    /// left on a clipboard that syncs to a Mac is a phrase in more places
    /// than anyone meant.
    private func copy() {
        UIPasteboard.general.setItems(
            [[UTType.utf8PlainText.identifier: RecoveryKey.formatted(phrase)]],
            options: [.localOnly: true, .expirationDate: Date.now.addingTimeInterval(120)]
        )
        withAnimation { copied = true }
    }
}

/// The phrase in big type, in groups of four, spelled out for VoiceOver.
struct PhraseText: View {
    let phrase: String

    private var formatted: String { RecoveryKey.formatted(phrase) }

    var body: some View {
        Text(formatted)
            .font(.system(.title2, design: .monospaced).weight(.semibold))
            .multilineTextAlignment(.center)
            .textSelection(.enabled)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 20)
            .padding(.horizontal, 12)
            .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            // One character at a time; VoiceOver would otherwise make words of
            // it, which is no use to someone copying it down.
            .accessibilityLabel(formatted.map { $0 == "-" ? "," : String($0) }.joined(separator: " "))
    }
}

/// Whether the parent said they'd written the phrase down. Until they do,
/// Caregivers keeps offering it.
enum RecoveryPhraseReminder {
    private static let key = "sync.phraseConfirmed"

    static var confirmed: Bool {
        get { UserDefaults.standard.bool(forKey: key) }
        set { UserDefaults.standard.set(newValue, forKey: key) }
    }
}

/// The phrase as a small text file, for Save to Files.
struct PhraseFile: Transferable {
    let phrase: String
    let babyName: String

    var text: String {
        """
        Baby Feed recovery phrase

        \(RecoveryKey.formatted(phrase))

        If every phone with \(babyName)'s log is lost, install Baby Feed, choose
        "Restore with recovery phrase" and type this in. Keep it somewhere safe:
        anyone with it can open the log.
        """
    }

    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(exportedContentType: .utf8PlainText) { file in
            let url = URL.temporaryDirectory.appending(path: "Baby Feed recovery phrase.txt")
            try Data(file.text.utf8).write(to: url, options: .atomic)
            return SentTransferredFile(url)
        }
    }
}

#Preview {
    RecoveryKeySetupView(phrase: RecoveryKey.generate(), babyName: "Nora") {}
}
