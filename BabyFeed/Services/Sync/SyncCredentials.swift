import Foundation
import Security

/// Where this phone keeps its pairing: which server, and the token that proves
/// it's allowed to talk to it.
///
/// The token goes in the Keychain rather than UserDefaults. It's the only
/// secret the app holds, it's equivalent to the whole log, and UserDefaults is
/// a plist in the app container that comes back in an unencrypted backup. The
/// server address is not a secret and lives in UserDefaults next to it, so the
/// Settings screen can read it without a Keychain round trip.
@MainActor
enum SyncCredentials {
    private static let serverKey = "sync.serverURL"
    private static let userIDKey = "sync.userID"
    private static let keychainAccount = "sync.deviceToken"
    private static let keychainService = "com.babyfeed.BabyFeed"

    /// The server this phone is paired with, e.g. `https://babyfeed.example.org:4443`.
    static var serverURL: URL? {
        get {
            guard let text = UserDefaults.standard.string(forKey: serverKey) else { return nil }
            return URL(string: text)
        }
        set { UserDefaults.standard.set(newValue?.absoluteString, forKey: serverKey) }
    }

    static var userID: UUID? {
        get { UserDefaults.standard.string(forKey: userIDKey).flatMap(UUID.init(uuidString:)) }
        set { UserDefaults.standard.set(newValue?.uuidString, forKey: userIDKey) }
    }

    static var token: String? {
        get {
            let query: [String: Any] = [
                kSecClass as String: kSecClassGenericPassword,
                kSecAttrService as String: keychainService,
                kSecAttrAccount as String: keychainAccount,
                kSecReturnData as String: true,
                kSecMatchLimit as String: kSecMatchLimitOne,
            ]
            var item: CFTypeRef?
            guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
                  let data = item as? Data else { return nil }
            return String(data: data, encoding: .utf8)
        }
        set {
            let query: [String: Any] = [
                kSecClass as String: kSecClassGenericPassword,
                kSecAttrService as String: keychainService,
                kSecAttrAccount as String: keychainAccount,
            ]
            SecItemDelete(query as CFDictionary)
            guard let value = newValue, let data = value.data(using: .utf8) else { return }
            var add = query
            add[kSecValueData as String] = data
            // Syncing must work when the phone is locked in a pocket at 4 a.m.,
            // so: after first unlock. ThisDeviceOnly because a token restored
            // onto a different phone should not still be paired.
            add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
            SecItemAdd(add as CFDictionary, nil)
        }
    }

    static var isPaired: Bool { serverURL != nil && token != nil }

    static func save(serverURL: URL, token: String, userID: UUID?) {
        self.serverURL = serverURL
        self.token = token
        self.userID = userID
    }

    /// Unpairs this phone. The local SwiftData store is deliberately untouched:
    /// the log on this phone is the source of truth and signing out of a server
    /// is not a reason to lose it.
    static func clear() {
        serverURL = nil
        userID = nil
        token = nil
        UserDefaults.standard.removeObject(forKey: "sync.watermarks")
    }
}
