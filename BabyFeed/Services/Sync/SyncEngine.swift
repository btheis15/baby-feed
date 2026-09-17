import Foundation
import Observation
import SwiftData

/// Where syncing would happen. Right now: nowhere.
///
/// The app is local-first by design – every screen reads the on-device
/// SwiftData store, and that store is the source of truth. Nothing in this file
/// is needed for the app to work; syncing exists only so more than one
/// caregiver can follow the same baby.
///
/// The Supabase client this used to hold is gone. A self-hosted server on the
/// Mac Mini will replace it, and the pieces such a client needs are
/// deliberately still here:
///
/// - Every row carries `uuid`, `updatedAt`, a soft `deletedAt` and
///   `needsUpload`, so changes can be queued and conflicts resolved.
/// - `SyncMerge` holds the merge rules – last writer wins, keeping an unpushed
///   local edit on ties – transport-agnostic and tested.
/// - `SyncDTOs` holds the row shapes, still snake_case for a Postgres table.
/// - The watermarks below record how far a pull got for each baby.
///
/// What's left is a client: push rows where `needsUpload` is true, pull rows
/// the server has touched since the watermark, hand each to `SyncMerge`. No
/// caller above this file has to change when that arrives.
@Observable
@MainActor
final class SyncEngine {
    static let shared = SyncEngine()

    enum Status: Equatable {
        /// No server configured, so everything stays on this iPhone.
        case localOnly
        case idle(lastSync: Date?)
        case syncing
        case error(String)
    }

    private(set) var status: Status = .localOnly

    private var container: ModelContainer?

    private init() {}

    /// True once a sync server is configured. Always false today.
    var isConfigured: Bool { false }

    var lastSyncDate: Date? {
        if case .idle(let date) = status { return date }
        return nil
    }

    func start(container: ModelContainer) {
        self.container = container
        status = .localOnly
    }

    /// Called after every local change. A no-op while there's no server, which
    /// is why every call site can stay exactly as it is.
    func requestSync() {
        guard isConfigured else { return }
    }

    // MARK: Watermarks

    /// How far the last pull for a baby got, so the next one asks only for rows
    /// the server has touched since. Kept despite there being no server,
    /// because it's the first thing a client will need.
    private static let watermarkKey = "sync.watermarks"

    static func watermark(for babyID: UUID) -> Date? {
        let all = UserDefaults.standard.dictionary(forKey: watermarkKey) as? [String: Double] ?? [:]
        guard let seconds = all[babyID.uuidString] else { return nil }
        return Date(timeIntervalSince1970: seconds)
    }

    /// Never moves backwards, so a slow response can't rewind progress.
    static func setWatermark(_ date: Date, for babyID: UUID) {
        var all = UserDefaults.standard.dictionary(forKey: watermarkKey) as? [String: Double] ?? [:]
        let existing = all[babyID.uuidString] ?? 0
        all[babyID.uuidString] = max(existing, date.timeIntervalSince1970)
        UserDefaults.standard.set(all, forKey: watermarkKey)
    }
}

enum SyncError: LocalizedError {
    case notConfigured

    var errorDescription: String? {
        switch self {
        case .notConfigured:
            "There's no sync server set up yet, so everything stays on this iPhone."
        }
    }
}
