import Foundation
import Observation
import SwiftData
#if canImport(UIKit)
import UIKit
#endif

/// Syncing. Push what this phone changed, pull what the other phone changed,
/// and let `SyncMerge` decide anything that collides.
///
/// The app stays local-first: the on-device SwiftData store is still the source
/// of truth and every screen still reads it. Nothing here is on the path
/// between tapping Save and seeing the feed in the list — a phone with no
/// signal, or no server configured at all, works exactly as before. Syncing is
/// what makes the *other* caregiver's phone agree, afterwards.
///
/// The server is the self-hosted one in `server/`, on the Mac mini. There is no
/// account and no third party: this phone holds a device token, the token names
/// a caregiver, and a caregiver can only see the babies they're a member of.
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
    /// The other caregivers on the current baby, as the server last listed them.
    private(set) var members: [MemberDTO] = []

    private var container: ModelContainer?
    private var isSyncing = false
    /// Set when a change lands mid-sync, so it isn't left sitting until the
    /// next one. A feed logged while a pull is in flight still goes up.
    private var syncAgain = false
    private var lastSyncDateValue: Date?

    private init() {}

    var isConfigured: Bool { SyncCredentials.isPaired }

    var lastSyncDate: Date? { lastSyncDateValue }

    private var client: SyncClient? {
        guard let url = SyncCredentials.serverURL, let token = SyncCredentials.token else { return nil }
        return SyncClient(baseURL: url, token: token)
    }

    func start(container: ModelContainer) {
        self.container = container
        status = isConfigured ? .idle(lastSync: nil) : .localOnly
        requestSync()
    }

    /// Called after every local change, and on foreground. Cheap and safe to
    /// call constantly: it does nothing without a server, and collapses into
    /// the sync already running.
    func requestSync() {
        guard isConfigured else {
            status = .localOnly
            return
        }
        guard !isSyncing else {
            syncAgain = true
            return
        }
        Task { await sync() }
    }

    /// Runs a sync and waits for it — for pull-to-refresh, where the point is
    /// that the spinner stops when the work is actually finished.
    func syncNow() async {
        guard isConfigured else { return }
        guard !isSyncing else { return }
        await sync()
    }

    // MARK: The sync itself

    private func sync() async {
        guard let container, let client else { return }
        isSyncing = true
        syncAgain = false
        status = .syncing
        let context = container.mainContext

        do {
            try await push(using: client, context: context)
            try await pullAll(using: client, context: context)
            lastSyncDateValue = .now
            status = .idle(lastSync: lastSyncDateValue)
        } catch SyncError.unpaired {
            // The token was revoked from another phone or the server was
            // rebuilt. Say so plainly rather than retrying forever; the log on
            // this phone is untouched either way.
            SyncCredentials.clear()
            status = .error("This phone was unpaired from the server. Pair it again under Caregivers.")
        } catch {
            status = .error((error as? LocalizedError)?.errorDescription ?? error.localizedDescription)
        }

        isSyncing = false
        if syncAgain { requestSync() }
    }

    // MARK: Push

    private func push(using client: SyncClient, context: ModelContext) async throws {
        let userID = SyncCredentials.userID
        let shared = sharedBabies(in: context)
        guard !shared.isEmpty else { return }
        let sharedIDs = Set(shared.map(\.uuid))

        var payload = SyncPushPayload()
        payload.babies = shared.filter(\.needsUpload).map { BabyDTO(baby: $0, createdBy: userID) }

        let feeds = fetch(FeedEntry.self, in: context).filter {
            $0.needsUpload && $0.babyID.map(sharedIDs.contains) == true
        }
        payload.feeds = feeds.compactMap { FeedDTO(entry: $0, userID: userID ?? UUID()) }

        let weights = fetch(WeightEntry.self, in: context).filter {
            $0.needsUpload && $0.babyID.map(sharedIDs.contains) == true
        }
        payload.weights = weights.compactMap { WeightDTO(entry: $0, userID: userID ?? UUID()) }

        let notes = fetch(CareNote.self, in: context).filter {
            $0.needsUpload && $0.babyID.map(sharedIDs.contains) == true
        }
        payload.careNotes = notes.compactMap { CareNoteDTO(entry: $0, userID: userID) }

        let diapers = fetch(DiaperEntry.self, in: context).filter {
            $0.needsUpload && $0.babyID.map(sharedIDs.contains) == true
        }
        payload.diapers = diapers.compactMap { DiaperDTO(entry: $0, userID: userID) }

        guard !payload.isEmpty else { return }
        let result = try await client.push(payload)

        // Clear the queue only for rows the server confirmed. "kept" counts:
        // it means the server holds a newer copy, which the pull just below is
        // about to bring back, so there is nothing left to upload.
        let accepted = Set(result.applied.map(\.id))
        for baby in shared where accepted.contains(baby.uuid) { baby.needsUpload = false }
        for feed in feeds where feed.uuid.map(accepted.contains) == true { feed.needsUpload = false }
        for weight in weights where weight.uuid.map(accepted.contains) == true { weight.needsUpload = false }
        for note in notes where note.uuid.map(accepted.contains) == true { note.needsUpload = false }
        for diaper in diapers where diaper.uuid.map(accepted.contains) == true { diaper.needsUpload = false }
        try? context.save()

        if !result.rejected.isEmpty {
            // Left queued on purpose: a rejected row is a bug, and a row that
            // silently stops trying is a feed that quietly never reaches the
            // other phone.
            throw SyncError.rejected(count: result.rejected.count,
                                     reason: result.rejected.first?.reason ?? "unknown")
        }
    }

    // MARK: Pull

    private func pullAll(using client: SyncClient, context: ModelContext) async throws {
        for baby in sharedBabies(in: context) {
            try await pull(babyID: baby.uuid, using: client, context: context)
        }
    }

    private func pull(babyID: UUID, using client: SyncClient, context: ModelContext) async throws {
        // A pull is capped server-side, so keep going while there's more. The
        // loop is bounded so a server that always says "more" can't hang here.
        for _ in 0..<20 {
            let since = Self.watermark(for: babyID)
            let result = try await client.pull(babyID: babyID, since: since)
            apply(result, babyID: babyID, in: context)

            if let next = SyncMerge.nextWatermark(previous: since, seen: result.serverStamps) {
                Self.setWatermark(next, for: babyID)
            }
            if !result.hasMore || result.isEmpty { break }
        }
    }

    private func apply(_ result: SyncClient.PullResult, babyID: UUID, in context: ModelContext) {
        if babyID == AppSettings.currentBabyID { members = result.members }

        for dto in result.babies {
            let local = BabyStore.baby(withID: dto.id, in: context)
            if let local {
                guard SyncMerge.remoteWins(remoteUpdatedAt: dto.updatedAt,
                                           localUpdatedAt: local.updatedAt,
                                           localNeedsUpload: local.needsUpload) else { continue }
                dto.apply(to: local)
                // The Baby tab reads a UserDefaults mirror of the current baby;
                // without this, the other caregiver's name change would be in
                // the database and invisible on screen.
                BabyStore.mirrorToDefaults(local)
            } else {
                let baby = Baby(uuid: dto.id, name: dto.name, birthDate: dto.birthDate)
                context.insert(baby)
                dto.apply(to: baby)
            }
        }

        merge(result.feeds, in: context, key: \FeedEntry.uuid,
              apply: { dto, entry in dto.apply(to: entry) },
              newRow: { FeedEntry(uuid: $0.id, kind: .formula) })
        merge(result.weights, in: context, key: \WeightEntry.uuid,
              apply: { dto, entry in dto.apply(to: entry) },
              newRow: { WeightEntry(uuid: $0.id, grams: 0) })
        merge(result.careNotes, in: context, key: \CareNote.uuid,
              apply: { dto, entry in dto.apply(to: entry) },
              newRow: { CareNote(uuid: $0.id, kind: .other) })
        merge(result.diapers, in: context, key: \DiaperEntry.uuid,
              apply: { dto, entry in dto.apply(to: entry) },
              newRow: { DiaperEntry(uuid: $0.id, kind: .wet) })

        try? context.save()
        // Everything derived from the log — the next-feed countdown, the
        // widget, the reminder, the Live Activity — is recomputed here rather
        // than by each screen, so a feed the other caregiver logged moves the
        // alarm on this phone too.
        // triggerSync: false — this IS the sync; asking it to start another
        // one from inside itself is how you get a loop.
        FeedCoordinator.feedsDidChange(in: context, triggerSync: false)
    }

    /// Shared merge path for the three row types. Each one is: find the local
    /// row by uuid, ask `SyncMerge` whether the server's copy should win, and
    /// insert it if this phone has never seen it.
    private func merge<DTO: SyncRow, Model: PersistentModel & SyncableRow>(
        _ rows: [DTO],
        in context: ModelContext,
        key: KeyPath<Model, UUID?>,
        apply: (DTO, Model) -> Void,
        newRow: (DTO) -> Model
    ) {
        guard !rows.isEmpty else { return }
        let existing = fetch(Model.self, in: context)
        var byID: [UUID: Model] = [:]
        for row in existing {
            if let id = row[keyPath: key] { byID[id] = row }
        }
        for dto in rows {
            if let local = byID[dto.id] {
                guard SyncMerge.remoteWins(remoteUpdatedAt: dto.updatedAt,
                                           localUpdatedAt: local.updatedAt,
                                           localNeedsUpload: local.needsUpload) else { continue }
                apply(dto, local)
            } else {
                // A row that arrives already deleted is one this phone never
                // had and never will — inserting a tombstone to hide it again
                // is pure work.
                guard dto.deletedAt == nil else { continue }
                let row = newRow(dto)
                context.insert(row)
                apply(dto, row)
            }
        }
    }

    // MARK: Pairing

    /// Pairs this phone as the owner, using the setup code from the Mac mini,
    /// and shares the babies already on it.
    func claim(serverURL: URL, secret: String, displayName: String, context: ModelContext) async throws {
        let client = SyncClient(baseURL: serverURL, token: nil)
        _ = try await client.health()
        let pairing = try await client.claim(secret: secret, displayName: displayName,
                                             deviceName: Self.deviceName)
        SyncCredentials.save(serverURL: serverURL, token: pairing.token, userID: pairing.userID)
        AppSettings.displayName = displayName.isEmpty ? pairing.displayName : displayName
        share(BabyStore.allBabies(in: context), in: context)
        status = .idle(lastSync: nil)
        await sync()
    }

    /// Joins a baby someone else already shares, with their invite code.
    func join(serverURL: URL, code: String, displayName: String, context: ModelContext) async throws {
        let client = SyncClient(baseURL: serverURL, token: nil)
        _ = try await client.health()
        // A phone that joined by scanning a QR never typed a name, and the
        // server keeps whatever it's given — including nothing, which would
        // leave this caregiver's feeds with no "Logged by" at all. The device
        // name is the one thing it can offer unprompted that the other phone
        // will recognise, and it's editable under Caregivers afterwards.
        let claimedName = displayName.isEmpty ? Self.deviceName : displayName
        let pairing = try await client.join(code: SyncMerge.normalizedInviteCode(code),
                                            displayName: claimedName,
                                            deviceName: Self.deviceName)
        SyncCredentials.save(serverURL: serverURL, token: pairing.token, userID: pairing.userID)
        AppSettings.displayName = pairing.displayName.isEmpty ? claimedName : pairing.displayName

        // Switch to the baby just joined, so the app lands on the shared log
        // rather than the empty placeholder this phone started with.
        if let dto = pairing.baby {
            let baby = BabyStore.baby(withID: dto.id, in: context) ?? {
                let fresh = Baby(uuid: dto.id, name: dto.name, birthDate: dto.birthDate)
                context.insert(fresh)
                return fresh
            }()
            dto.apply(to: baby)
            try? context.save()
            BabyStore.setCurrent(baby, in: context)
        }
        status = .idle(lastSync: nil)
        await sync()
    }

    // MARK: Recovery

    /// Makes sure this baby has a recovery key, and hands back the key itself.
    ///
    /// Idempotent: if this phone already holds one it's returned as-is, so
    /// opening the screen twice doesn't quietly retire the key somebody has
    /// already written down.
    func recoveryKey(for babyID: UUID) async throws -> String {
        guard let client else { throw SyncError.notConfigured }
        if let existing = RecoveryKey.stored(for: babyID) { return existing }

        let key = RecoveryKey.generate()
        try await client.setRecoveryKeyHash(RecoveryKey.hash(key), babyID: babyID)
        RecoveryKey.store(key, for: babyID)
        return key
    }

    /// Retires whatever key existed and issues a new one. The old one stops
    /// working the moment the server takes the new hash.
    func replaceRecoveryKey(for babyID: UUID) async throws -> String {
        guard let client else { throw SyncError.notConfigured }
        let key = RecoveryKey.generate()
        try await client.setRecoveryKeyHash(RecoveryKey.hash(key), babyID: babyID)
        RecoveryKey.store(key, for: babyID)
        return key
    }

    /// Whether the server has a key for this baby, which is not the same as
    /// this phone holding one — a caregiver who joined by QR has neither.
    func serverHasRecoveryKey(for babyID: UUID) async -> Bool {
        guard let client else { return false }
        return (try? await client.recoveryStatus(babyID: babyID))?.exists ?? false
    }

    /// Takes a written-down key and gets the log back.
    ///
    /// Works on a phone with nothing on it, and on one that's already paired —
    /// in which case the recovered baby joins the caregiver this phone already
    /// is, so recovering a second log doesn't cost you the first.
    func recover(serverURL: URL, key: String, context: ModelContext) async throws {
        guard RecoveryKey.isPlausible(key) else { throw SyncError.badRecoveryKey }
        let existingToken = SyncCredentials.serverURL == serverURL ? SyncCredentials.token : nil
        let client = SyncClient(baseURL: serverURL, token: existingToken)
        _ = try await client.health()

        let pairing = try await client.recover(key: key,
                                               displayName: AppSettings.displayName,
                                               deviceName: Self.deviceName)
        SyncCredentials.save(serverURL: serverURL,
                             token: pairing.token.isEmpty ? (existingToken ?? "") : pairing.token,
                             userID: pairing.userID)
        if !pairing.displayName.isEmpty { AppSettings.displayName = pairing.displayName }

        if let dto = pairing.baby {
            let baby = BabyStore.baby(withID: dto.id, in: context) ?? {
                let fresh = Baby(uuid: dto.id, name: dto.name, birthDate: dto.birthDate)
                context.insert(fresh)
                return fresh
            }()
            dto.apply(to: baby)
            // The phone that recovered it now holds the key too, so it can be
            // shown again here without another trip to the server.
            RecoveryKey.store(RecoveryKey.normalized(key), for: dto.id)
            try? context.save()
            BabyStore.setCurrent(baby, in: context)
        }
        status = .idle(lastSync: nil)
        await sync()
    }

    /// Marks babies as shared and queues them, which is what makes the server
    /// create them and this caregiver their owner.
    func share(_ babies: [Baby], in context: ModelContext) {
        for baby in babies where !baby.isShared {
            baby.isShared = true
            baby.markChanged()
            // Rows created before sharing existed have never been uploaded.
            queueEverything(for: baby.uuid, in: context)
        }
        try? context.save()
    }

    private func queueEverything(for babyID: UUID, in context: ModelContext) {
        for feed in fetch(FeedEntry.self, in: context) where feed.babyID == babyID { feed.needsUpload = true }
        for weight in fetch(WeightEntry.self, in: context) where weight.babyID == babyID { weight.needsUpload = true }
        for note in fetch(CareNote.self, in: context) where note.babyID == babyID { note.needsUpload = true }
        for diaper in fetch(DiaperEntry.self, in: context) where diaper.babyID == babyID { diaper.needsUpload = true }
    }

    func createInvite(babyID: UUID) async throws -> SyncClient.Invite {
        guard let client else { throw SyncError.notConfigured }
        return try await client.createInvite(babyID: babyID)
    }

    func refreshMembers(babyID: UUID) async {
        guard let client else { return }
        members = (try? await client.members(babyID: babyID)) ?? members
    }

    func updateDisplayName(_ name: String) async {
        AppSettings.displayName = name
        guard let client else { return }
        try? await client.setDisplayName(name)
    }

    /// Unpairs this phone. The log stays; only the link to the server goes.
    func unpair(context: ModelContext) {
        SyncCredentials.clear()
        for baby in BabyStore.allBabies(in: context) {
            baby.isShared = false
            baby.ownerUserID = nil
        }
        try? context.save()
        members = []
        lastSyncDateValue = nil
        status = .localOnly
    }

    private static var deviceName: String {
        #if canImport(UIKit)
        return UIDevice.current.name
        #else
        return "iPhone"
        #endif
    }

    // MARK: Helpers

    private func sharedBabies(in context: ModelContext) -> [Baby] {
        fetch(Baby.self, in: context).filter(\.isShared)
    }

    private func fetch<T: PersistentModel>(_ type: T.Type, in context: ModelContext) -> [T] {
        (try? context.fetch(FetchDescriptor<T>())) ?? []
    }

    // MARK: Watermarks

    /// How far the last pull for a baby got, so the next one asks only for rows
    /// the server has touched since.
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

/// The two things the merge path needs from a row, whatever kind it is.
protocol SyncRow {
    var id: UUID { get }
    var updatedAt: Date { get }
    var deletedAt: Date? { get }
}

extension FeedDTO: SyncRow {}
extension WeightDTO: SyncRow {}
extension CareNoteDTO: SyncRow {}
extension DiaperDTO: SyncRow {}

protocol SyncableRow: AnyObject {
    var updatedAt: Date { get }
    var needsUpload: Bool { get set }
}

extension FeedEntry: SyncableRow {}
extension WeightEntry: SyncableRow {}
extension CareNote: SyncableRow {}
extension DiaperEntry: SyncableRow {}

enum SyncError: LocalizedError {
    case notConfigured
    case unpaired
    case badServerURL
    case unreachable(String)
    case server(status: Int, message: String, code: String?)
    case badResponse(String)
    case rejected(count: Int, reason: String)
    case badRecoveryKey

    var errorDescription: String? {
        switch self {
        case .notConfigured:
            "There's no sync server set up yet, so everything stays on this iPhone."
        case .unpaired:
            "This phone isn't paired with the server."
        case .badServerURL:
            "That server address doesn't look right."
        case .unreachable(let detail):
            "Couldn't reach the server. \(detail)"
        case .server(_, let message, _):
            message
        case .badResponse:
            "The server sent something this version of the app didn't understand."
        case .rejected(let count, let reason):
            "The server wouldn't accept \(count == 1 ? "a row" : "\(count) rows"): \(reason)"
        case .badRecoveryKey:
            "A recovery key is \(RecoveryKey.length) letters and numbers. Check for a missed character."
        }
    }
}
