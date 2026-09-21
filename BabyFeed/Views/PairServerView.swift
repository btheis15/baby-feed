import SwiftData
import SwiftUI

/// Connecting this phone to the server on the Mac mini.
///
/// Two ways in, and which one you are is not a question anybody should have to
/// answer twice: the phone that set the server up types the setup code from the
/// mini, and every phone after that arrives here from a link or a QR code with
/// the address and the invite code already filled in.
struct PairServerView: View {
    /// Prefilled when this opened from a `babyfeed://join` link.
    var invitation: SyncLink.Invitation?

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @AppStorage(AppSettings.displayNameKey) private var displayName = ""

    private enum Mode: String, CaseIterable {
        case join, first, recover

        var title: String {
            switch self {
            case .join: "Invited"
            case .first: "First phone"
            case .recover: "Recovery key"
            }
        }
    }

    @State private var mode: Mode = .join
    @State private var serverText = ""
    @State private var code = ""
    @State private var name = ""
    @State private var isWorking = false
    @State private var errorMessage: String?
    /// So a redraw can't fire a second join for the same invitation.
    @State private var hasJoinedAutomatically = false

    private var serverURL: URL? { SyncLink.normalizedServerURL(serverText) }

    private var canSubmit: Bool {
        guard !isWorking, serverURL != nil else { return false }
        let hasName = !name.trimmingCharacters(in: .whitespaces).isEmpty
        switch mode {
        case .join:
            // Arriving from a QR code or a link, the name is optional. The scan
            // already carried the address and the code, the server names this
            // caregiver if we don't, and the name is editable under Caregivers
            // afterwards — so there's nothing here worth stopping for.
            guard hasName || invitation != nil else { return false }
            return SyncMerge.isPlausibleInviteCode(code)
        case .first:
            guard hasName else { return false }
            return code.trimmingCharacters(in: .whitespaces).count >= 6
        case .recover:
            // No name needed: the key says which log, and the name on this
            // phone is whatever it already was.
            return RecoveryKey.isPlausible(code)
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
                    TextField("babyfeed.example.org", text: $serverText)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .keyboardType(.URL)
                } header: {
                    Text("Server address")
                } footer: {
                    Text(serverFooter)
                }

                Section {
                    TextField(codeTitle, text: $code, axis: mode == .recover ? .vertical : .horizontal)
                        .textInputAutocapitalization(.characters)
                        .autocorrectionDisabled()
                        .font(.system(.body, design: .monospaced))
                } header: {
                    Text(codeTitle)
                } footer: {
                    Text(codeFooter)
                }

                if mode != .recover {
                    Section {
                        TextField("Your name", text: $name)
                            .textInputAutocapitalization(.words)
                    } header: {
                        Text("Your name")
                    } footer: {
                        Text("Shown next to everything you log, so the other caregiver can tell your entries from theirs.")
                    }
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
                            if isWorking { ProgressView() } else { Text(submitTitle) }
                            Spacer()
                        }
                    }
                    .disabled(!canSubmit)
                }
            }
            .navigationTitle("Set up sharing")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
            .onAppear(perform: prefill)
        }
    }

    private var submitTitle: String {
        switch mode {
        case .join: "Join"
        case .first: "Connect"
        case .recover: "Get the log back"
        }
    }

    private var codeTitle: String {
        switch mode {
        case .join: "Invite code"
        case .first: "Setup code"
        case .recover: "Recovery key"
        }
    }

    private var codeFooter: String {
        switch mode {
        case .join: "Six letters and numbers, from the phone that's already set up."
        case .first: "Printed by the setup script on the Mac mini. You only need it once."
        case .recover: "The \(RecoveryKey.length) characters you wrote down. Dashes and spaces don't matter."
        }
    }

    private var serverFooter: String {
        if let url = serverURL, url.scheme == "http" {
            return "Plain http, so this only works on your home Wi-Fi. Fine for trying it out."
        }
        return "The address of the server on your Mac mini."
    }

    private func prefill() {
        if name.isEmpty { name = displayName }
        if let invitation {
            mode = .join
            code = invitation.code
            serverText = invitation.server.absoluteString
            // Scanning the other phone's QR, or opening its link, is itself the
            // handoff: it's phone-to-phone, it carries the address and a
            // one-shot code, and it can't happen by accident. So this screen
            // doesn't stop to be filled in — it just connects.
            if !hasJoinedAutomatically {
                hasJoinedAutomatically = true
                submit()
            }
        } else if let existing = SyncCredentials.serverURL {
            serverText = existing.absoluteString
        }
    }

    private func submit() {
        guard canSubmit, let serverURL else { return }
        let trimmedName = name.trimmingCharacters(in: .whitespaces)
        isWorking = true
        errorMessage = nil
        Task {
            do {
                switch mode {
                case .first:
                    try await SyncEngine.shared.claim(
                        serverURL: serverURL,
                        secret: code.trimmingCharacters(in: .whitespaces),
                        displayName: trimmedName,
                        context: modelContext)
                case .join:
                    try await SyncEngine.shared.join(
                        serverURL: serverURL,
                        code: code,
                        displayName: trimmedName,
                        context: modelContext)
                case .recover:
                    try await SyncEngine.shared.recover(
                        serverURL: serverURL,
                        key: code,
                        context: modelContext)
                }
                // Left alone when blank, so joining without typing a name keeps
                // the one the server just handed out rather than clearing it.
                if !trimmedName.isEmpty { displayName = trimmedName }
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
        .modelContainer(for: [FeedEntry.self, WeightEntry.self, Baby.self, CareNote.self], inMemory: true)
}
