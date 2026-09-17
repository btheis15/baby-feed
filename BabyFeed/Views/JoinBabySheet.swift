import SwiftData
import SwiftUI

/// Enter an invite code to follow another caregiver's baby.
struct JoinBabySheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    @State private var code: String
    @State private var isWorking = false
    @State private var errorMessage: String?
    @State private var showSignIn = false

    private let engine = SyncEngine.shared

    init(initialCode: String = "") {
        _code = State(initialValue: SyncMerge.normalizedInviteCode(initialCode))
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Invite code", text: $code)
                        .textInputAutocapitalization(.characters)
                        .autocorrectionDisabled()
                        .font(.system(.title2, design: .monospaced))
                        .onChange(of: code) { _, new in
                            let cleaned = SyncMerge.normalizedInviteCode(new)
                            if cleaned != new { code = cleaned }
                        }
                } footer: {
                    Text("Ask the person who set up the baby to send you a code from Settings → Caregivers.")
                }

                if !engine.isConfigured {
                    Section {
                        Text("Sync isn't set up in this build yet.")
                            .foregroundStyle(.secondary)
                    }
                } else if !engine.isSignedIn {
                    Section {
                        Text("Sign in first so the log can be shared with you.")
                        Button("Sign in") { showSignIn = true }
                    }
                }

                if let errorMessage {
                    Section {
                        Text(errorMessage)
                            .foregroundStyle(.red)
                            .font(.footnote)
                    }
                }
            }
            .navigationTitle("Join a baby")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Join") { join() }
                        .disabled(!SyncMerge.isPlausibleInviteCode(code) || !engine.isSignedIn || isWorking)
                }
            }
            .overlay {
                if isWorking { ProgressView() }
            }
            .sheet(isPresented: $showSignIn) {
                SignInSheet()
            }
        }
        .presentationDetents([.medium, .large])
    }

    private func join() {
        isWorking = true
        errorMessage = nil
        Task {
            do {
                _ = try await engine.join(code: code, in: modelContext)
                dismiss()
            } catch {
                errorMessage = error.localizedDescription
            }
            isWorking = false
        }
    }
}

#Preview {
    JoinBabySheet(initialCode: "ABC123")
        .modelContainer(for: [FeedEntry.self, WeightEntry.self, Baby.self], inMemory: true)
}
