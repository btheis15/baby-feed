import AuthenticationServices
import CryptoKit
import SwiftUI

/// Sign in with Apple, or a 6-digit code by email. Only used for sharing.
struct SignInSheet: View {
    @Environment(\.dismiss) private var dismiss

    @State private var nonce = ""
    @State private var email = ""
    @State private var code = ""
    @State private var codeSent = false
    @State private var isWorking = false
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    SignInWithAppleButton(.continue) { request in
                        nonce = Self.randomNonce()
                        request.requestedScopes = [.fullName, .email]
                        request.nonce = Self.sha256(nonce)
                    } onCompletion: { result in
                        handleApple(result)
                    }
                    .signInWithAppleButtonStyle(.black)
                    .frame(height: 50)
                    .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
                } footer: {
                    Text("Your Apple ID is used only to sign you in. Feeds are shared only with caregivers you invite.")
                }

                Section("Or use your email") {
                    TextField("Email address", text: $email)
                        .keyboardType(.emailAddress)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .disabled(codeSent)
                    if codeSent {
                        TextField("6-digit code from the email", text: $code)
                            .keyboardType(.numberPad)
                        Button("Verify code") { verifyCode() }
                            .disabled(code.count < 6 || isWorking)
                        Button("Use a different email") {
                            codeSent = false
                            code = ""
                        }
                    } else {
                        Button("Email me a code") { sendCode() }
                            .disabled(!email.contains("@") || isWorking)
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
            .navigationTitle("Sign in")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
            .overlay {
                if isWorking { ProgressView() }
            }
        }
        .presentationDetents([.medium, .large])
    }

    // MARK: Apple

    private func handleApple(_ result: Result<ASAuthorization, Error>) {
        switch result {
        case .failure(let error):
            // Cancelling the sheet is not an error worth showing.
            if (error as? ASAuthorizationError)?.code != .canceled {
                errorMessage = error.localizedDescription
            }
        case .success(let authorization):
            guard let credential = authorization.credential as? ASAuthorizationAppleIDCredential,
                  let tokenData = credential.identityToken,
                  let token = String(data: tokenData, encoding: .utf8) else {
                errorMessage = "Apple didn't return a sign-in token. Try again."
                return
            }
            isWorking = true
            Task {
                do {
                    try await SyncEngine.shared.signInWithApple(
                        idToken: token,
                        nonce: nonce,
                        givenName: credential.fullName?.givenName,
                        familyName: credential.fullName?.familyName
                    )
                    dismiss()
                } catch {
                    errorMessage = error.localizedDescription
                }
                isWorking = false
            }
        }
    }

    // MARK: Email

    private func sendCode() {
        isWorking = true
        errorMessage = nil
        Task {
            do {
                try await SyncEngine.shared.sendEmailCode(to: email.trimmingCharacters(in: .whitespaces))
                codeSent = true
            } catch {
                errorMessage = error.localizedDescription
            }
            isWorking = false
        }
    }

    private func verifyCode() {
        isWorking = true
        errorMessage = nil
        Task {
            do {
                try await SyncEngine.shared.verifyEmailCode(email: email.trimmingCharacters(in: .whitespaces), code: code.trimmingCharacters(in: .whitespaces))
                dismiss()
            } catch {
                errorMessage = error.localizedDescription
            }
            isWorking = false
        }
    }

    // MARK: Nonce

    private static func randomNonce() -> String {
        (UUID().uuidString + UUID().uuidString).replacingOccurrences(of: "-", with: "")
    }

    private static func sha256(_ input: String) -> String {
        SHA256.hash(data: Data(input.utf8)).map { String(format: "%02x", $0) }.joined()
    }
}

#Preview {
    SignInSheet()
}
