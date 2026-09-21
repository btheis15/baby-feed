import AuthenticationServices
import CryptoKit
import Foundation

/// Signing in with Apple, which is how a caregiver proves they're the same
/// person on a phone that isn't the one they paired.
///
/// There is deliberately no password, no email and no sign-up form anywhere in
/// Baby Feed. The whole of it is one button: Apple vouches for who you are,
/// the server keeps the identifier Apple gives it, and that's the account.
///
/// What it protects against is narrow and worth being exact about. The device
/// token is device-bound on purpose, so a wiped or replaced phone loses it —
/// and only an owner can issue invites, which left an owner with no way back
/// into their own log. This closes that, and nothing else: it is not a gate in
/// front of the app, and a phone that never signs in works exactly as before.
enum AppleSignIn {
    /// What the app needs back from a completed authorisation.
    struct Result {
        var identityToken: String
        var rawNonce: String
        /// Apple hands over a name only the first time someone authorises this
        /// app, and never again. Empty on every later sign-in.
        var displayName: String
    }

    /// A fresh nonce per attempt, so an identity token captured from one
    /// sign-in can't be replayed into another.
    static func newNonce() -> String {
        var bytes = [UInt8](repeating: 0, count: 32)
        guard SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes) == errSecSuccess else {
            // Can't get randomness, can't make a safe nonce. A UUID pair is a
            // poor substitute but is still unpredictable enough to not reuse.
            return UUID().uuidString + UUID().uuidString
        }
        return Data(bytes).base64EncodedString()
    }

    /// Apple is handed the hash; the raw value goes to our server, which hashes
    /// it the same way and checks the two agree.
    static func hashed(_ nonce: String) -> String {
        SHA256.hash(data: Data(nonce.utf8)).map { String(format: "%02x", $0) }.joined()
    }

    /// Fills in the request Apple's button hands us. Kept here rather than at
    /// the call site so the nonce is hashed exactly once, in one place.
    static func prepare(_ request: ASAuthorizationAppleIDRequest, nonce: String) {
        request.requestedScopes = [.fullName]
        request.nonce = hashed(nonce)
    }

    /// Pulls what we need out of a successful authorisation.
    static func result(from authorization: ASAuthorization, nonce: String) throws -> Result {
        guard let credential = authorization.credential as? ASAuthorizationAppleIDCredential,
              let data = credential.identityToken,
              let token = String(data: data, encoding: .utf8) else {
            throw SyncError.badResponse("Apple didn't return a usable sign-in token.")
        }
        return Result(identityToken: token,
                      rawNonce: nonce,
                      displayName: name(from: credential.fullName))
    }

    private static func name(from components: PersonNameComponents?) -> String {
        guard let components else { return "" }
        let formatted = PersonNameComponentsFormatter.localizedString(from: components, style: .default)
        return formatted.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
