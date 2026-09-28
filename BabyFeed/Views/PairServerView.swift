import SwiftData
import SwiftUI

/// Connecting by hand: a typed server address with an invite code or a
/// recovery phrase. For the edge cases only (a link that didn't say which
/// server, a Mac mini that moved). The everyday ways in are the QR, the link,
/// and "Restore with recovery phrase" on the first screen, none of which ask
/// for an address.
struct PairServerView: View {
    /// Prefilled when this opened from a link that carried a code but no server.
    var code: String?

    @Environment(\.dismiss) private var dismiss

    private enum Mode: String, CaseIterable {
        case join, recover

        var title: String {
            switch self {
            case .join: "Invite code"
            case .recover: "Recovery phrase"
            }
        }
    }

    @State private var mode: Mode = .join
    @State private var serverText = ""
    @State private var codeText = ""
    @State private var isWorking = false
    @State private var errorMessage: String?

    private var serverURL: URL? { SyncLink.normalizedServerURL(serverText) }

    private var canSubmit: Bool {
        guard !isWorking, serverURL != nil else { return false }
        switch mode {
        case .join: return SyncMerge.isPlausibleInviteCode(codeText)
        case .recover: return RecoveryKey.isPlausible(codeText)
        }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("", selection: $mode) {
                        ForEach(Mode.allCases, id: \.self) { Text($0.title).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                }

                Section {
                    TextField("your-mac-mini.local:8791", text: $serverText)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .keyboardType(.URL)
                } header: {
                    Text("Server address")
                } footer: {
                    Text(serverFooter)
                }

                Section {
                    TextField(mode.title, text: $codeText, axis: mode == .recover ? .vertical : .horizontal)
                        .textInputAutocapitalization(.characters)
                        .autocorrectionDisabled()
                        .font(.system(.body, design: .monospaced))
                } header: {
                    Text(mode.title)
                } footer: {
                    Text(mode == .join
                         ? "Six letters and numbers, from the phone that has the log (Share)."
                         : "The \(RecoveryKey.length) characters you wrote down. Dashes and spaces don't matter.")
                }

                if let errorMessage {
                    Section {
                        Text(errorMessage).foregroundStyle(.red).font(.footnote)
                    }
                }

                Section {
                    Button {
                        submit()
                    } label: {
                        HStack {
                            Spacer()
                            if isWorking { ProgressView() } else { Text(mode == .join ? "Join" : "Restore") }
                            Spacer()
                        }
                    }
                    .disabled(!canSubmit)
                }
            }
            .navigationTitle("Connect by hand")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
            .onAppear(perform: prefill)
        }
    }

    private var serverFooter: String {
        if let url = serverURL, url.scheme == "http" {
            return "Plain http, so this only works on your home Wi‑Fi."
        }
        return "The address of the Baby Feed server on your Mac mini."
    }

    private func prefill() {
        if let code { codeText = code }
        if serverText.isEmpty, let known = SyncCredentials.serverURL ?? ServerConfig.current {
            serverText = known.absoluteString
        }
    }

    private func submit() {
        guard canSubmit, let serverURL else { return }
        isWorking = true
        errorMessage = nil
        Task {
            do {
                switch mode {
                case .join:
                    _ = try await SyncEngine.shared.join(SyncLink.Invitation(code: codeText, server: serverURL))
                case .recover:
                    try await SyncEngine.shared.recover(key: codeText, serverURL: serverURL)
                }
                dismiss()
            } catch {
                errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            }
            isWorking = false
        }
    }
}

#Preview {
    PairServerView()
        .modelContainer(.preview)
}
