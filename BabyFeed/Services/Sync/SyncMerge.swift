import Foundation

/// Pure decisions the sync engine makes. Kept free of SwiftData and network
/// code so they can be unit-tested.
enum SyncMerge {
    /// Should the server's copy overwrite the local one?
    /// Last writer wins by `updatedAt`. A local edit that hasn't been pushed
    /// yet is kept unless the remote change is strictly newer.
    static func remoteWins(remoteUpdatedAt: Date, localUpdatedAt: Date, localNeedsUpload: Bool) -> Bool {
        if localNeedsUpload {
            return remoteUpdatedAt > localUpdatedAt
        }
        return remoteUpdatedAt >= localUpdatedAt
    }

    /// "abc 123" → "ABC123". Users type codes with spaces, dashes, lowercase.
    static func normalizedInviteCode(_ input: String) -> String {
        String(input.uppercased().filter { $0.isLetter || $0.isNumber })
    }

    static let inviteCodeLength = 6

    static func isPlausibleInviteCode(_ input: String) -> Bool {
        normalizedInviteCode(input).count == inviteCodeLength
    }

    /// Text the owner sends to another caregiver.
    static func inviteMessage(babyName: String, code: String) -> String {
        "Join \(babyName)'s feeding log in Baby Feed. Open the app, sign in, and enter code \(code), or tap: babyfeed://join/\(code)"
    }

    /// The watermark for the next pull: newest server timestamp seen, minus a
    /// small overlap so nothing falls between two pulls.
    static func nextWatermark(previous: Date?, seen: [Date]) -> Date? {
        guard let newest = seen.max() else { return previous }
        let candidate = newest.addingTimeInterval(-1)
        if let previous { return max(previous, candidate) }
        return candidate
    }

    /// First-time display name from Sign in with Apple or an email address.
    static func suggestedDisplayName(givenName: String?, familyName: String?, email: String?) -> String {
        let given = givenName?.trimmingCharacters(in: .whitespaces) ?? ""
        if !given.isEmpty { return given }
        let family = familyName?.trimmingCharacters(in: .whitespaces) ?? ""
        if !family.isEmpty { return family }
        if let email, let local = email.split(separator: "@").first, !local.isEmpty {
            return String(local)
        }
        return ""
    }
}
