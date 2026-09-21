import AuthenticationServices
import SwiftUI

/// Apple's own button, with the nonce handled so no call site has to think
/// about it: a fresh one per attempt, hashed on the way to Apple and kept raw
/// for the server to check against.
struct AppleSignInButton: View {
    var label: SignInWithAppleButton.Label = .signIn
    var onResult: (AppleSignIn.Result) -> Void
    var onFailure: (Error) -> Void

    @Environment(\.colorScheme) private var colorScheme
    @State private var nonce = AppleSignIn.newNonce()

    var body: some View {
        SignInWithAppleButton(label) { request in
            // Rolled here rather than at init, so a second attempt after a
            // cancel or a failure doesn't reuse the first one's nonce.
            nonce = AppleSignIn.newNonce()
            AppleSignIn.prepare(request, nonce: nonce)
        } onCompletion: { outcome in
            switch outcome {
            case .success(let authorization):
                do {
                    onResult(try AppleSignIn.result(from: authorization, nonce: nonce))
                } catch {
                    onFailure(error)
                }
            case .failure(let error):
                // Backing out isn't a failure, and saying so in red would be
                // the app arguing with someone who already decided.
                if (error as? ASAuthorizationError)?.code == .canceled { return }
                onFailure(error)
            }
        }
        .signInWithAppleButtonStyle(colorScheme == .dark ? .white : .black)
        .frame(height: 48)
        .accessibilityIdentifier("SignInWithApple")
    }
}
