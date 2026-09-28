import CryptoKit
import Foundation
import Security

/// The last way back into a baby's log, the way a wallet has a seed phrase.
///
/// This phone makes the key and keeps it. The server is told only a SHA-256 of
/// it, which means the server — and its backups, and anyone who ends up with a
/// copy of the database — holds nothing that opens a log, and also that the
/// server can never show anyone their key again. Only a phone that has it can,
/// which is exactly why the app can reveal it on demand.
///
/// Twenty-four characters in six groups, from the same alphabet as an invite
/// code: no I, O, 0 or 1, because this gets copied onto paper by someone who
/// has not slept.
enum RecoveryKey {
    static let groupCount = 6
    static let groupSize = 4
    static let length = groupCount * groupSize

    /// Matches CODE_ALPHABET in the server's auth.js.
    private static let alphabet = Array("ABCDEFGHJKLMNPQRSTUVWXYZ23456789")

    static func generate() -> String {
        var bytes = [UInt8](repeating: 0, count: length)
        if SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes) != errSecSuccess {
            // Without real randomness there is no safe key to make, and a
            // predictable one is worse than none: it would look like a
            // backstop while being guessable.
            for index in bytes.indices { bytes[index] = UInt8.random(in: .min ... .max) }
        }
        return String(bytes.map { alphabet[Int($0) % alphabet.count] })
    }

    /// What the server stores, and the only form it ever sees.
    static func hash(_ key: String) -> String {
        SHA256.hash(data: Data(normalized(key).utf8)).map { String(format: "%02x", $0) }.joined()
    }

    /// "abcd efgh-JKLM…" -> "ABCDEFGHJKLM…". Mirrors normalizeCode server-side.
    static func normalized(_ input: String) -> String {
        input.uppercased().filter { $0.isLetter || $0.isNumber }
    }

    static func isPlausible(_ input: String) -> Bool {
        let key = normalized(input)
        return key.count == length && key.allSatisfy { alphabet.contains($0) }
    }

    /// Grouped for reading aloud and writing down.
    static func formatted(_ key: String) -> String {
        let key = normalized(key)
        return stride(from: 0, to: key.count, by: groupSize).map { offset in
            let start = key.index(key.startIndex, offsetBy: offset)
            let end = key.index(start, offsetBy: min(groupSize, key.count - offset))
            return String(key[start..<end])
        }.joined(separator: "-")
    }

    // MARK: Keychain
    //
    // Stored per baby, and marked synchronizable so it rides iCloud Keychain to
    // the person's other devices. That is deliberately different from the
    // device token next door, which is ThisDeviceOnly: a token is this phone's
    // permission and shouldn't outlive it, whereas the recovery key is the
    // backstop and is worth having on the iPad too. The written-down copy is
    // still the real backup — iCloud Keychain is convenience, not the plan.

    private static let service = "com.babyfeed.BabyFeed.recovery"

    private static func query(for babyID: UUID) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: babyID.uuidString,
            kSecAttrSynchronizable as String: kCFBooleanTrue as Any,
        ]
    }

    static func stored(for babyID: UUID) -> String? {
        var lookup = query(for: babyID)
        lookup[kSecReturnData as String] = true
        lookup[kSecMatchLimit as String] = kSecMatchLimitOne
        var item: CFTypeRef?
        guard SecItemCopyMatching(lookup as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    @discardableResult
    static func store(_ key: String, for babyID: UUID) -> Bool {
        SecItemDelete(query(for: babyID) as CFDictionary)
        var add = query(for: babyID)
        add[kSecValueData as String] = Data(key.utf8)
        // Not ThisDeviceOnly: it has to be able to sync. After first unlock so
        // it's never readable from a phone that hasn't been unlocked since boot.
        add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        return SecItemAdd(add as CFDictionary, nil) == errSecSuccess
    }

    static func forget(for babyID: UUID) {
        SecItemDelete(query(for: babyID) as CFDictionary)
    }
}
