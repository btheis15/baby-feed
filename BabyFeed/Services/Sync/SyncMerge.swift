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

    /// Text sent with an invite link. The whole link, server and all: the
    /// older server-less `babyfeed://join/CODE` dead-ended on a new phone.
    static func inviteMessage(babyName: String, link: URL) -> String {
        "Join \(babyName)'s log in Baby Feed. Open this link on your iPhone (Baby Feed must be installed): \(link.absoluteString)"
    }

    /// The watermark for the next pull: newest server timestamp seen, minus a
    /// small overlap so nothing falls between two pulls.
    static func nextWatermark(previous: Date?, seen: [Date]) -> Date? {
        guard let newest = seen.max() else { return previous }
        let candidate = newest.addingTimeInterval(-1)
        if let previous { return max(previous, candidate) }
        return candidate
    }
}
