import Foundation

/// The decisions `SyncEngine` makes about connecting, as small pure functions,
/// so each can be tested without a server, a Keychain or a store.
enum SyncPlan {
    /// Why the app is reaching for the server.
    enum ConnectReason: Equatable {
        /// A baby was just added: back it up.
        case addedBaby
        /// "Back up now", on the card for installs from before sharing.
        case backUp
        /// Share was tapped.
        case share
        /// The app came to the front, or something changed.
        case foreground
    }

    /// Whether to reach for the network at all. Anything the parent asked for
    /// goes ahead. Coming to the front only reconnects a phone that has been
    /// connected, or was asked to be, and hasn't been told to stop: so the
    /// Local Network prompt never turns up unexplained on a cold launch, and
    /// a phone that only ever joined never makes an identity of its own.
    static func shouldConnect(for reason: ConnectReason, wantsSync: Bool, optedOut: Bool) -> Bool {
        switch reason {
        case .foreground: wantsSync && !optedOut
        case .addedBaby, .backUp, .share: true
        }
    }

    /// Whether this server can do what the app needs: set a phone up with
    /// nothing typed, and let an already-paired phone join as itself.
    static func isCompatible(_ health: SyncClient.Health) -> Bool {
        (health.api ?? 1) >= 2 && health.supports("enroll") && health.supports("join_as_member")
    }

    enum ServerIdentity: Equatable {
        /// The same database as last time.
        case same
        /// Never seen an id from it before (it's new to this phone, or this
        /// phone is from before servers had ids). Take it as it is.
        case firstSeen
        /// A different database: it was reset, so this phone's token means
        /// nothing there and everything has to be sent again.
        case reset
    }

    static func identity(stored: String?, reported: String?) -> ServerIdentity {
        guard let reported else { return .same }
        guard let stored else { return .firstSeen }
        return stored == reported ? .same : .reset
    }

    /// An untouched placeholder: what a fresh install starts with before
    /// anyone names a baby or logs anything. Joining or restoring replaces
    /// it, and it's never uploaded.
    static func isPlaceholder(name: String, birthDate: Date?, isShared: Bool, rowCount: Int) -> Bool {
        name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && birthDate == nil && !isShared && rowCount == 0
    }

    /// The babies a push was refused for because this caregiver is no longer
    /// on them: the owner took them off the log. Those stop syncing and stay
    /// on this phone; retrying them forever would only fail forever.
    static func babiesNoLongerShared(
        rejected: [SyncClient.PushResult.Rejected],
        babyOfRow: (_ table: String, _ id: UUID) -> UUID?
    ) -> Set<UUID> {
        var babies = Set<UUID>()
        for rejection in rejected where rejection.code == "not_a_member" {
            guard let id = rejection.id else { continue }
            if let baby = babyOfRow(rejection.table, id) { babies.insert(baby) }
        }
        return babies
    }

    /// After the server stops accepting this phone's token, try setting up
    /// again at most once an hour rather than on every tap.
    static func mayReconnect(lastAttempt: Date?, now: Date, every interval: TimeInterval = 3600) -> Bool {
        guard let lastAttempt else { return true }
        return now.timeIntervalSince(lastAttempt) >= interval
    }

    /// What to say while the phone isn't at home.
    static func awayText(pending: Int) -> String {
        switch pending {
        case 0: "Will sync when you're home"
        case 1: "Will sync when you're home · 1 change waiting"
        default: "Will sync when you're home · \(pending) changes waiting"
        }
    }
}
