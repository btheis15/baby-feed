import CryptoKit
import Foundation
import Security

/// End-to-end encryption for babies added from this build on ("sealed" logs).
///
/// Each sealed baby has its own random 256-bit key, made on the phone that
/// adds the baby. Every row is encrypted with it before it leaves the phone,
/// its kind and its deletion included, so the Mac mini stores only which baby
/// a row belongs to, when it last changed, and bytes it can't read. Whoever
/// runs the server can't open a sealed log; nor can a copy of its database.
///
/// The key reaches the other caregiver's phone inside the QR (the Camera app
/// hands the link straight to Baby Feed; it never goes to the server), and
/// comes back after a lost phone through the parent's recovery phrase: a key
/// made from the phrase locks a copy of the baby's key, and that locked copy
/// is what the server keeps. Lose the phrase and every phone, and the log is
/// gone for good: nobody, including the server, can bring it back.
///
/// Babies from before stay readable on the server and sync exactly as they
/// always have. Nothing here touches them.
enum SealedLog {
    /// What each box is bound to, so the server can't move one onto another
    /// row or another baby and have it open.
    static func rowContext(id: UUID, babyID: UUID) -> Data {
        Data("babyfeed.sealed.v1|\(id.uuidString)|\(babyID.uuidString)".utf8)
    }

    static func keyContext(babyID: UUID) -> Data {
        Data("babyfeed.babykey.v1|\(babyID.uuidString)".utf8)
    }

    static func nameContext(babyID: UUID, userID: UUID) -> Data {
        Data("babyfeed.name.v1|\(babyID.uuidString)|\(userID.uuidString)".utf8)
    }

    enum Failure: Error, Equatable {
        /// A box that doesn't open with this key: tampered with, or for a
        /// different baby.
        case cannotOpen
        case unknownTable(String)
    }

    // MARK: Boxes

    static func seal(_ plaintext: Data, key: SymmetricKey, context: Data) throws -> String {
        let box = try AES.GCM.seal(plaintext, using: key, authenticating: context)
        // `combined` is only nil for a nonce of a non-standard size, which
        // `seal` never makes.
        guard let combined = box.combined else { throw Failure.cannotOpen }
        return combined.base64EncodedString()
    }

    static func open(_ sealed: String, key: SymmetricKey, context: Data) throws -> Data {
        guard let data = Data(base64Encoded: sealed) else { throw Failure.cannotOpen }
        do {
            return try AES.GCM.open(try AES.GCM.SealedBox(combined: data), using: key, authenticating: context)
        } catch {
            throw Failure.cannotOpen
        }
    }

    // MARK: Rows

    /// Inside every box: which table the row is from, and the row itself as
    /// the same JSON a readable log sends.
    private struct Envelope<Row: Codable>: Codable {
        let table: String
        let row: Row
    }

    private struct Header: Decodable {
        let table: String
    }

    /// A row as it travels for a sealed baby.
    struct Row: Codable, Equatable {
        let id: UUID
        let babyID: UUID
        let updatedAt: Date
        let sealed: String
        var serverUpdatedAt: Date? = nil

        enum CodingKeys: String, CodingKey {
            case id, sealed
            case babyID = "baby_id"
            case updatedAt = "updated_at"
            case serverUpdatedAt = "server_updated_at"
        }
    }

    static func sealRow<DTO: Codable>(_ dto: DTO, table: String, id: UUID, babyID: UUID, updatedAt: Date,
                                      key: SymmetricKey) throws -> Row {
        let plaintext = try SyncClient.encoder.encode(Envelope(table: table, row: dto))
        let sealed = try seal(plaintext, key: key, context: rowContext(id: id, babyID: babyID))
        return Row(id: id, babyID: babyID, updatedAt: updatedAt, sealed: sealed)
    }

    /// What a box held: its table, and the row's JSON to decode as that table.
    static func openRow(_ row: Row, key: SymmetricKey) throws -> (table: String, json: Data) {
        let plaintext = try open(row.sealed, key: key, context: rowContext(id: row.id, babyID: row.babyID))
        let header = try SyncClient.decoder.decode(Header.self, from: plaintext)
        return (header.table, plaintext)
    }

    private struct Opened<Row: Decodable>: Decodable {
        let row: Row
    }

    static func decode<DTO: Decodable>(_ type: DTO.Type, from json: Data) throws -> DTO {
        try SyncClient.decoder.decode(Opened<DTO>.self, from: json).row
    }

    // MARK: Names

    /// A caregiver's name on a sealed log, readable only with its key.
    static func sealName(_ name: String, babyID: UUID, userID: UUID, key: SymmetricKey) throws -> String {
        try seal(Data(name.utf8), key: key, context: nameContext(babyID: babyID, userID: userID))
    }

    static func openName(_ sealed: String, babyID: UUID, userID: UUID, key: SymmetricKey) -> String? {
        guard let data = try? open(sealed, key: key, context: nameContext(babyID: babyID, userID: userID)) else {
            return nil
        }
        return String(data: data, encoding: .utf8)
    }

    // MARK: Phrase-locked keys

    /// The key a recovery phrase makes, for locking baby keys. HKDF rather
    /// than the phrase's SHA-256, which is what the server holds to recognise
    /// the phrase: knowing that hash gives nothing towards this.
    static func phraseKey(_ phrase: String) -> SymmetricKey {
        HKDF<SHA256>.deriveKey(
            inputKeyMaterial: SymmetricKey(data: Data(RecoveryKey.normalized(phrase).utf8)),
            salt: Data("babyfeed.phrase-key.v1".utf8),
            info: Data("baby keys".utf8),
            outputByteCount: 32
        )
    }

    static func lock(_ babyKey: SymmetricKey, babyID: UUID, phrase: String) throws -> String {
        let raw = babyKey.withUnsafeBytes { Data($0) }
        return try seal(raw, key: phraseKey(phrase), context: keyContext(babyID: babyID))
    }

    static func unlock(_ wrapped: String, babyID: UUID, phrase: String) throws -> SymmetricKey {
        SymmetricKey(data: try open(wrapped, key: phraseKey(phrase), context: keyContext(babyID: babyID)))
    }
}

/// Each sealed baby's key, in the Keychain.
///
/// Synchronizable, like the recovery phrase, so it rides iCloud Keychain to
/// the person's other devices; the phrase is still the real backup. Under
/// `babykey:<baby id>` in the recovery service, which no phrase account uses.
enum BabyKey {
    private static let service = "com.babyfeed.BabyFeed.recovery"

    static func account(for babyID: UUID) -> String { "babykey:\(babyID.uuidString)" }

    static func generate() -> SymmetricKey { SymmetricKey(size: .bits256) }

    private static func query(for babyID: UUID) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account(for: babyID),
            kSecAttrSynchronizable as String: kCFBooleanTrue as Any,
        ]
    }

    static func stored(for babyID: UUID) -> SymmetricKey? {
        var lookup = query(for: babyID)
        lookup[kSecReturnData as String] = true
        lookup[kSecMatchLimit as String] = kSecMatchLimitOne
        var item: CFTypeRef?
        guard SecItemCopyMatching(lookup as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data, data.count == 32 else { return nil }
        return SymmetricKey(data: data)
    }

    @discardableResult
    static func store(_ key: SymmetricKey, for babyID: UUID) -> Bool {
        SecItemDelete(query(for: babyID) as CFDictionary)
        var add = query(for: babyID)
        add[kSecValueData as String] = key.withUnsafeBytes { Data($0) }
        add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        return SecItemAdd(add as CFDictionary, nil) == errSecSuccess
    }

    static func forget(for babyID: UUID) {
        SecItemDelete(query(for: babyID) as CFDictionary)
    }

    /// The key as it rides in a QR: base64url, no padding, 43 characters.
    static func linkText(_ key: SymmetricKey) -> String {
        key.withUnsafeBytes { Data($0) }.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    static func fromLinkText(_ text: String) -> SymmetricKey? {
        var base64 = text.replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        while base64.count % 4 != 0 { base64 += "=" }
        guard let data = Data(base64Encoded: base64), data.count == 32 else { return nil }
        return SymmetricKey(data: data)
    }
}
