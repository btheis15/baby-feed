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
        case join, first

        var title: String {
            switch self {
            case .join: "I was invited"
            case .first: "This is the first phone"
            }
        }
    }

    @State private var mode: Mode = .join
    @State private var serverText = ""
    @State private var code = ""
    @State private var name = ""
    @State private var isWorking = false
    @State private var errorMessage: String?

    private var serverURL: URL? { SyncLink.normalizedServerURL(serverText) }

    private var canSubmit: Bool {
        guard !isWorking, serverURL != nil, !name.trimmingCharacters(in: .whitespaces).isEmpty else { return false }
        switch mode {
        case .join: return SyncMerge.isPlausibleInviteCode(code)
        case .first: return code.trimmingCharacters(in: .whitespaces).count >= 6
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
                    TextField(mode == .join ? "Invite code" : "Setup code", text: $code)
                        .textInputAutocapitalization(.characters)
                        .autocorrectionDisabled()
                        .font(.system(.body, design: .monospaced))
                } header: {
                    Text(mode == .join ? "Invite code" : "Setup code")
                } footer: {
                    Text(mode == .join
                         ? "Six letters and numbers, from the phone that's already set up."
                         : "Printed by the setup script on the Mac mini. You only need it once.")
                }

                Section {
                    TextField("Your name", text: $name)
                        .textInputAutocapitalization(.words)
                } header: {
                    Text("Your name")
                } footer: {
                    Text("Shown next to everything you log, so the other caregiver can tell your entries from theirs.")
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
                            if isWorking { ProgressView() } else { Text(mode == .join ? "Join" : "Connect") }
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
        } else if let existing = SyncCredentials.serverURL {
            serverText = existing.absoluteString
        }
    }

    private func submit() {
        guard let serverURL else { return }
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
                }
                displayName = trimmedName
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
