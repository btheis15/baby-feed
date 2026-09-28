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
/// A phone gets its token by setting itself up on the home Wi‑Fi, by scanning
/// another phone's QR, or with its parent's recovery phrase — never by typing.
@Observable
@MainActor
final class SyncEngine {
    static let shared = SyncEngine()

    enum Status: Equatable {
        /// Not connected, so everything stays on this iPhone.
        case localOnly
        case idle(lastSync: Date?)
        case syncing
        /// Not on the home Wi‑Fi (or the Mac mini is off). Calm, not an error:
        /// the changes wait and go up when the phone is home.
        case away(pending: Int)
        /// The Mac mini's server is from before sharing without credentials.
        case needsUpdate
        case error(String)
    }

    /// Where this parent's recovery phrase stands, as last checked.
    enum PhraseState: Equatable {
        case unknown
        /// The phrase on this phone is the one the server knows.
        case matches
        /// Another phone set up a different phrase since.
        case differs
        /// This phone has a phrase the server hasn't been told about yet.
        case notRegistered
        /// The server has a phrase, and this phone doesn't hold a copy.
        case notOnThisPhone
    }

    private(set) var status: Status = .localOnly
    /// The other caregivers on the current baby, as the server last listed them.
    private(set) var members: [MemberDTO] = []
    private(set) var phraseState: PhraseState = .unknown

    private var container: ModelContainer?
    private var isSyncing = false
    /// Set when a change lands mid-sync, so it isn't left sitting until the
    /// next one. A feed logged while a pull is in flight still goes up.
    private var syncAgain = false
    /// Whether this sync brought anything down, so everything derived from
    /// the log is refreshed once at the end rather than after every page.
    private var pulledChanges = false
    private var lastSyncDateValue: Date?
    /// `syncNow()` callers waiting on a sync that was already running.
    private var waiters: [CheckedContinuation<Void, Never>] = []
    /// Connect, join, restore and unpair take turns: each one reads and
    /// writes the credentials, and two at once could leave the phone holding
    /// a token for one identity and the user id of another.
    private let serial = SerialWork()
    /// The last automatic attempt to connect or reconnect, so being away from
    /// home costs one quick failure a minute rather than one per tap.
    private var lastAutomaticAttempt: Date?
    private var lastReconnect: Date?
    private var lastAdoption: Date?

    private init() {}

    var isConfigured: Bool { SyncCredentials.isPaired }

    var lastSyncDate: Date? { lastSyncDateValue }

    /// Whether this build knows a server to use.
    var hasServer: Bool { SyncCredentials.serverURL != nil || ServerConfig.current != nil }

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
            // A phone that asked to be backed up and hasn't managed it yet (it
            // was set up away from home) keeps trying, quietly.
            if SyncPlan.shouldConnect(for: .foreground, wantsSync: SyncCredentials.wantsSync,
                                      optedOut: SyncCredentials.optedOut) {
                connectInBackground()
            } else {
                status = .localOnly
            }
            return
        }
        guard !isSyncing else {
            syncAgain = true
            return
        }
        // Away from home, one quick failure a minute is enough. A diaper
        // logged in the car doesn't need its own attempt.
        if case .away = status, let last = lastAutomaticAttempt, Date.now.timeIntervalSince(last) < 60 {
            if let context = container?.mainContext { status = .away(pending: pendingCount(in: context)) }
            return
        }
        // Claimed here rather than inside the Task. Launch and every
        // foreground ask twice in the same moment, and with the flag only set
        // once the Task started, both calls got past the check and two syncs
        // ran side by side.
        isSyncing = true
        Task { await sync() }
    }

    /// Runs a sync and waits for it, including one that was already running
    /// and whatever it has to run again: Share has to know the baby is on the
    /// server before it asks for an invite.
    func syncNow() async {
        guard isConfigured else { return }
        if isSyncing {
            syncAgain = true
            await withCheckedContinuation { waiters.append($0) }
            return
        }
        isSyncing = true
        await sync()
    }

    private func connectInBackground() {
        let now = Date.now
        if let last = lastAutomaticAttempt, now.timeIntervalSince(last) < 60 { return }
        lastAutomaticAttempt = now
        Task { try? await ensureConnected(.foreground) }
    }

    // MARK: Connecting

    /// Makes sure this phone is connected, setting it up if it has never been:
    /// find the server (the saved address, or the one this build was made
    /// for), check it's the same database as before, enrol with this parent's
    /// recovery phrase if the phone isn't paired, back up every real baby, and
    /// sync.
    ///
    /// Returns false when it decided not to try (coming to the front on a
    /// phone that has never been asked to connect). Throws `.away` when the
    /// server can't be reached, which callers show calmly.
    @discardableResult
    func ensureConnected(_ reason: SyncPlan.ConnectReason) async throws -> Bool {
        try await serial.run { try await self.connect(reason) }
    }

    private func connect(_ reason: SyncPlan.ConnectReason) async throws -> Bool {
        guard SyncPlan.shouldConnect(for: reason, wantsSync: SyncCredentials.wantsSync,
                                     optedOut: SyncCredentials.optedOut) else { return false }
        // Setting up without being asked is only for a phone with its own
        // phrase waiting: one set up away from home, or one carrying its
        // phrase over a server reset. A phone that joined by QR scans again.
        if reason == .foreground, !SyncCredentials.isPaired,
           RecoveryPhrase.stored(account: RecoveryPhrase.pendingAccount) == nil {
            return false
        }
        guard let container else { throw SyncError.notConfigured }
        let context = container.mainContext
        if reason != .foreground {
            // An explicit ask undoes "Stop syncing", and is remembered, so a
            // phone set up away from home connects once it's back.
            SyncCredentials.optedOut = false
            SyncCredentials.connectionRequested = true
        }

        let (url, health) = try await findServer(context: context)

        if SyncCredentials.isPaired {
            switch SyncPlan.identity(stored: SyncCredentials.serverID, reported: health.serverID) {
            case .same, .firstSeen:
                // The saved address failed but the build's own one answered as
                // the same server: it moved, so follow it.
                if SyncCredentials.serverURL != url { SyncCredentials.serverURL = url }
                if let id = health.serverID { SyncCredentials.serverID = id }
            case .reset:
                // A new database: this phone's token means nothing there. Set
                // up again, and send everything, as if for the first time.
                carryPhraseForward()
                SyncCredentials.clear()
                requeueEverything(in: context)
            }
        }

        if !SyncCredentials.isPaired {
            try await enroll(at: url, health: health, context: context)
        }

        share(BabyStore.realBabies(in: context), in: context)
        await syncNow()
        await refreshPhraseState()
        return true
    }

    /// The saved address, or the one this build was made for, whichever
    /// answers first.
    private func findServer(context: ModelContext) async throws -> (URL, SyncClient.Health) {
        var candidates: [URL] = []
        for url in [SyncCredentials.serverURL, ServerConfig.current].compactMap({ $0 }) where !candidates.contains(url) {
            candidates.append(url)
        }
        guard !candidates.isEmpty else { throw SyncError.notConfigured }

        var failure = SyncError.away
        for url in candidates {
            do {
                let health = try await SyncClient(baseURL: url, token: nil).probe()
                guard SyncPlan.isCompatible(health) else {
                    status = .needsUpdate
                    throw SyncError.serverNeedsUpdate
                }
                return (url, health)
            } catch SyncError.serverNeedsUpdate {
                throw SyncError.serverNeedsUpdate
            } catch {
                failure = SyncError.classify(error)
            }
        }
        if failure == .away { status = .away(pending: pendingCount(in: context)) }
        throw failure
    }

    /// Sets this phone up as a new caregiver, with this parent's recovery
    /// phrase, so no phone is ever paired without one.
    private func enroll(at url: URL, health: SyncClient.Health, context: ModelContext) async throws {
        // The server only enrols phones on its own Wi‑Fi. Say so rather than
        // try and be refused.
        guard health.enrollAvailable != false else {
            status = .away(pending: pendingCount(in: context))
            throw SyncError.away
        }
        let phrase = RecoveryPhrase.pendingOrNew()
        let client = SyncClient(baseURL: url, token: nil)
        do {
            let pairing = try await client.enroll(displayName: AppSettings.displayName,
                                                  deviceName: Self.deviceName,
                                                  keyHash: RecoveryKey.hash(phrase))
            guard let token = pairing.token else { throw SyncError.badResponse("No token in the enrolment") }
            SyncCredentials.save(serverURL: url, token: token, userID: pairing.userID,
                                 serverID: pairing.serverID ?? health.serverID)
            RecoveryPhrase.promotePending(to: pairing.userID)
            phraseState = .matches
        } catch let error as SyncError where error.code == "key_exists" {
            // The server already knows this phrase: an earlier attempt got
            // through and its answer didn't make it back. The phrase is the
            // proof of who this is, so restore with it.
            try await performRecover(key: phrase, url: url, context: context)
        }
    }

    // MARK: The sync itself

    /// Callers set `isSyncing` before calling, so two can't start at once.
    private func sync() async {
        guard let container, let client else {
            finishSync()
            return
        }
        isSyncing = true
        syncAgain = false
        pulledChanges = false
        status = .syncing
        let context = container.mainContext

        do {
            try await adoptBabies(using: client, context: context)
            try await push(using: client, context: context)
            let failures = try await pullAll(using: client, context: context)
            lastSyncDateValue = .now
            status = failures.isEmpty
                ? .idle(lastSync: lastSyncDateValue)
                : .error(failures[0])
        } catch SyncError.unpaired {
            // The server stopped accepting this token: its database was reset,
            // or this phone was removed. Either way the log here is untouched.
            if let token = client.token, SyncCredentials.token == token {
                carryPhraseForward()
                SyncCredentials.clear(ifToken: token)
                status = .localOnly
                reconnectAfterLosingToken(in: context)
            }
        } catch SyncError.away {
            lastAutomaticAttempt = .now
            status = .away(pending: pendingCount(in: context))
        } catch {
            status = .error((error as? LocalizedError)?.errorDescription ?? error.localizedDescription)
        }

        // Everything derived from the log — the countdown, the widget, the
        // reminder, the Live Activity — is recomputed here, once, and only if
        // a pull brought something new: a feed the other caregiver logged
        // moves the alarm on this phone too, and a sync that changed nothing
        // wakes nothing. triggerSync: false, because this IS the sync.
        if pulledChanges {
            FeedCoordinator.feedsDidChange(in: context, triggerSync: false)
        }
        finishSync()
    }

    private func finishSync() {
        isSyncing = false
        if syncAgain, isConfigured {
            isSyncing = true
            Task { await sync() }
            return
        }
        syncAgain = false
        let waiting = waiters
        waiters = []
        waiting.forEach { $0.resume() }
    }

    /// After a 401: set up again, at most once an hour. If the server was
    /// reset, this re-uploads the log. If this phone was taken off a log, the
    /// server refuses its rows and that log stops syncing here, which is the
    /// honest outcome.
    private func reconnectAfterLosingToken(in context: ModelContext) {
        // Only a phone that holds its parent's recovery phrase sets itself up
        // again: the phrase proves who it was. A phone that joined by QR has
        // no phrase of its own, and never makes an identity by itself.
        guard RecoveryPhrase.stored(account: RecoveryPhrase.pendingAccount) != nil else {
            status = .error("This phone lost its link to the log. On the other phone, tap Share, then scan the code again.")
            return
        }
        guard SyncPlan.mayReconnect(lastAttempt: lastReconnect, now: .now) else {
            status = .error("This phone lost its link to your Mac mini. Tap Share under Caregivers to set it up again.")
            return
        }
        lastReconnect = .now
        requeueEverything(in: context)
        Task { try? await ensureConnected(.backUp) }
    }

    /// Any log this person is on that the phone doesn't have yet: after a
    /// restore, or when someone added them from another phone. Checked on
    /// the first sync after launch and every ten minutes after, not on every
    /// tap.
    private func adoptBabies(using client: SyncClient, context: ModelContext) async throws {
        if let last = lastAdoption, Date.now.timeIntervalSince(last) < 600 { return }
        let account = try await client.me()
        lastAdoption = .now
        if SyncCredentials.serverID == nil, let id = account.serverID { SyncCredentials.serverID = id }
        adopt(account.babies, in: context)
        if let key = account.recoveryKey { updatePhraseState(serverHasPhrase: key.exists) }
    }

    // MARK: Push

    /// Rows per push. The server refuses a request over 2 MB, and a first
    /// backup of a few months is thousands of rows, so it goes up in batches.
    static let pushBatchSize = 400

    private func push(using client: SyncClient, context: ModelContext) async throws {
        let userID = SyncCredentials.userID
        let shared = sharedBabies(in: context)
        guard !shared.isEmpty else { return }
        let sharedIDs = Set(shared.map(\.uuid))
        func queued<T: PersistentModel & SyncableRow & CareEntry>(_ type: T.Type) -> [T] {
            fetch(type, in: context).filter { $0.needsUpload && $0.babyID.map(sharedIDs.contains) == true }
        }

        let babies = shared.filter(\.needsUpload)
        var rows: [any SyncableRow & CareEntry] = []
        rows += queued(FeedEntry.self) as [any SyncableRow & CareEntry]
        rows += queued(WeightEntry.self) as [any SyncableRow & CareEntry]
        rows += queued(CareNote.self) as [any SyncableRow & CareEntry]
        rows += queued(DiaperEntry.self) as [any SyncableRow & CareEntry]
        rows += queued(SolidFoodEntry.self) as [any SyncableRow & CareEntry]
        guard !babies.isEmpty || !rows.isEmpty else { return }

        // What was sent, by when it was last changed. A row edited again while
        // this push was in flight has a newer stamp by the time the answer
        // comes, and has to stay queued; clearing it regardless is how an edit
        // made mid-sync used to never reach the other phone.
        var sentAt: [UUID: Date] = [:]
        for baby in babies { sentAt[baby.uuid] = baby.updatedAt }
        for row in rows {
            if let id = row.uuid { sentAt[id] = row.updatedAt }
        }

        var rejected: [SyncClient.PushResult.Rejected] = []
        var next = 0
        var isFirstBatch = true
        repeat {
            let batch = Array(rows[next..<min(rows.count, next + Self.pushBatchSize)])
            next += batch.count
            var payload = SyncPushPayload()
            // Babies go in the first batch, ahead of their rows: a log starts
            // on the server when it first sees the baby.
            if isFirstBatch { payload.babies = babies.map { BabyDTO(baby: $0, createdBy: userID) } }
            payload.feeds = batch.compactMap { ($0 as? FeedEntry).flatMap { FeedDTO(entry: $0, userID: userID ?? UUID()) } }
            payload.weights = batch.compactMap { ($0 as? WeightEntry).flatMap { WeightDTO(entry: $0, userID: userID ?? UUID()) } }
            payload.careNotes = batch.compactMap { ($0 as? CareNote).flatMap { CareNoteDTO(entry: $0, userID: userID) } }
            payload.diapers = batch.compactMap { ($0 as? DiaperEntry).flatMap { DiaperDTO(entry: $0, userID: userID) } }
            payload.solidFoods = batch.compactMap { ($0 as? SolidFoodEntry).flatMap { SolidFoodDTO(entry: $0, userID: userID) } }
            let sentBabies = isFirstBatch ? babies : []
            isFirstBatch = false
            guard !payload.isEmpty else { continue }

            let result = try await client.push(payload)

            // Clear the queue only for rows the server confirmed. "kept"
            // counts: it means the server holds a newer copy, which the pull
            // just below is about to bring back, so there's nothing to upload.
            let accepted = Set(result.applied.map(\.id))
            func settle(_ id: UUID?, _ updatedAt: Date, _ clear: () -> Void) {
                guard let id, accepted.contains(id), sentAt[id] == updatedAt else { return }
                clear()
            }
            for baby in sentBabies { settle(baby.uuid, baby.updatedAt) { baby.needsUpload = false } }
            for row in batch {
                settle(row.uuid, row.updatedAt) { row.needsUpload = false }
            }
            try? context.save()
            rejected += result.rejected
        } while next < rows.count

        // Taken off a log by its owner: stop sending its rows, keep them here.
        var rowBabies: [UUID: UUID] = [:]
        for row in rows {
            if let id = row.uuid, let babyID = row.babyID { rowBabies[id] = babyID }
        }
        let dropped = SyncPlan.babiesNoLongerShared(rejected: rejected) { table, id in
            table == "babies" ? id : rowBabies[id]
        }
        for baby in shared where dropped.contains(baby.uuid) {
            baby.isShared = false
        }
        try? context.save()

        let other = rejected.filter { $0.code != "not_a_member" }
        if !dropped.isEmpty {
            let names = shared.filter { dropped.contains($0.uuid) }.map(\.displayName).joined(separator: ", ")
            throw SyncError.server(status: 403,
                                   message: "\(names) is no longer shared with you. The log stays on this iPhone.",
                                   code: "not_a_member")
        }
        if !other.isEmpty {
            // Left queued on purpose: a rejected row is a bug, and a row that
            // silently stops trying is a feed that quietly never reaches the
            // other phone.
            throw SyncError.rejected(count: other.count, reason: other.first?.reason ?? "unknown")
        }
    }

    // MARK: Pull

    /// Each baby on its own, so one that fails doesn't stop the others.
    /// Returns what went wrong, if anything.
    private func pullAll(using client: SyncClient, context: ModelContext) async throws -> [String] {
        var failures: [String] = []
        for baby in sharedBabies(in: context) {
            do {
                try await pull(babyID: baby.uuid, using: client, context: context)
            } catch SyncError.server(403, _, _) {
                // Taken off this log since: it stays here and stops syncing.
                baby.isShared = false
                try? context.save()
                failures.append("\(baby.displayName) is no longer shared with you. The log stays on this iPhone.")
            } catch let error as SyncError where error == .unpaired || error == .away {
                // Not about this baby: the caller deals with these.
                throw error
            } catch {
                failures.append((error as? LocalizedError)?.errorDescription ?? error.localizedDescription)
            }
        }
        return failures
    }

    private func pull(babyID: UUID, using client: SyncClient, context: ModelContext) async throws {
        // A pull is capped server-side, so keep going while there's more. The
        // loop is bounded so a server that always says "more" can't hang here;
        // at 500 rows a page that's still a year of a busy newborn's log.
        for _ in 0..<100 {
            let since = Self.watermark(for: babyID)
            let result = try await client.pull(babyID: babyID, since: since)
            apply(result, babyID: babyID, in: context)

            // The server's own cursor when it gives one: exact, so a long log
            // pages through whole. Guessing from the newest stamp (minus a
            // second) used to skip rows or never get past a big first backup.
            if let next = result.nextSince ?? SyncMerge.nextWatermark(previous: since, seen: result.serverStamps) {
                Self.setWatermark(next, for: babyID)
            }
            if !result.hasMore || (result.isEmpty && result.nextSince == nil) { break }
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
        merge(result.solidFoods, in: context, key: \SolidFoodEntry.uuid,
              apply: { dto, entry in dto.apply(to: entry) },
              newRow: { SolidFoodEntry(uuid: $0.id, name: "", texture: .puree) })

        try? context.save()
        if !result.isEmpty { pulledChanges = true }
    }

    /// Shared merge path for the row types. Each one is: find the local row
    /// by uuid, ask `SyncMerge` whether the server's copy should win, and
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

    // MARK: Joining and restoring

    struct Joined: Equatable {
        /// The log that was joined, when the server said which.
        let babyName: String?
        /// No name to log under yet: ask for one.
        let needsName: Bool
    }

    /// Joins a log from a scanned QR or a sent link. A phone that's already
    /// paired with this server joins as the caregiver it already is, so a
    /// second log doesn't cost it the first.
    func join(_ invitation: SyncLink.Invitation) async throws -> Joined {
        try await serial.run { try await self.performJoin(invitation) }
    }

    private func performJoin(_ invitation: SyncLink.Invitation) async throws -> Joined {
        guard let container else { throw SyncError.notConfigured }
        let context = container.mainContext
        SyncCredentials.optedOut = false

        let url = invitation.server
        let health = try await SyncClient(baseURL: url, token: nil).probe()
        guard SyncPlan.isCompatible(health) else { throw SyncError.serverNeedsUpdate }

        // Only offer this phone's token to the server that issued it, and only
        // one that understands it: an older server would mint a second
        // identity and quietly strand this phone's other logs.
        let sameServer = SyncCredentials.serverURL == url
            || (health.serverID != nil && health.serverID == SyncCredentials.serverID)
        let existingToken = sameServer ? SyncCredentials.token : nil
        let pairing = try await SyncClient(baseURL: url, token: existingToken)
            .join(code: SyncMerge.normalizedInviteCode(invitation.code),
                  displayName: AppSettings.displayName,
                  deviceName: Self.deviceName)
        guard let token = pairing.token ?? existingToken else {
            throw SyncError.badResponse("The server didn't hand this phone a token.")
        }
        SyncCredentials.save(serverURL: url, token: token, userID: pairing.userID,
                             serverID: pairing.serverID ?? health.serverID)
        if AppSettings.displayName.isEmpty, !pairing.displayName.isEmpty {
            AppSettings.displayName = pairing.displayName
        }

        adopt(pairing.babies, in: context)
        var joinedName: String?
        if let dto = pairing.baby {
            let baby = upsert(dto, in: context)
            joinedName = baby.displayName
            BabyStore.setCurrent(baby, in: context)
            BabyStore.removePlaceholders(keeping: baby.uuid, in: context)
        }
        lastAdoption = .now
        await syncNow()
        return Joined(babyName: joinedName, needsName: AppSettings.displayName.isEmpty)
    }

    /// Takes a written-down phrase and gets every log it covers back. Works on
    /// a phone with nothing on it, and on one that's already paired, which the
    /// server folds into the person the phrase belongs to.
    func recover(key: String, serverURL: URL? = nil) async throws {
        guard RecoveryKey.isPlausible(key) else { throw SyncError.badRecoveryKey }
        guard let container else { throw SyncError.notConfigured }
        guard let url = serverURL ?? SyncCredentials.serverURL ?? ServerConfig.current else {
            throw SyncError.notConfigured
        }
        try await serial.run { try await self.performRecover(key: key, url: url, context: container.mainContext) }
    }

    private func performRecover(key: String, url: URL, context: ModelContext) async throws {
        SyncCredentials.optedOut = false
        SyncCredentials.connectionRequested = true
        let health = try await SyncClient(baseURL: url, token: nil).probe()
        let existingToken = SyncCredentials.serverURL == url ? SyncCredentials.token : nil
        let pairing = try await SyncClient(baseURL: url, token: existingToken)
            .recover(key: key, displayName: AppSettings.displayName, deviceName: Self.deviceName)
        guard let token = pairing.token ?? existingToken else {
            throw SyncError.badResponse("The server didn't hand this phone a token.")
        }
        SyncCredentials.save(serverURL: url, token: token, userID: pairing.userID,
                             serverID: pairing.serverID ?? health.serverID)
        if !pairing.displayName.isEmpty { AppSettings.displayName = pairing.displayName }

        let normalized = RecoveryKey.normalized(key)
        if pairing.wasPersonalPhrase {
            RecoveryPhrase.store(normalized, account: RecoveryPhrase.account(for: pairing.userID))
            if RecoveryPhrase.stored(account: RecoveryPhrase.pendingAccount) == normalized {
                RecoveryPhrase.forget(account: RecoveryPhrase.pendingAccount)
            }
            phraseState = .matches
        } else if let babyID = pairing.baby?.id {
            // An older per-baby key: kept where the older builds kept it.
            RecoveryKey.store(normalized, for: babyID)
        }

        adopt(pairing.babies, in: context)
        let restored = pairing.baby.map { upsert($0, in: context) }
            ?? BabyStore.currentBaby(in: context).flatMap { $0.isShared ? $0 : nil }
            ?? BabyStore.allBabies(in: context).first(where: \.isShared)
        if let restored {
            BabyStore.setCurrent(restored, in: context)
            BabyStore.removePlaceholders(keeping: restored.uuid, in: context)
        }
        lastAdoption = .now
        await syncNow()
    }

    /// Inserts (or updates) every log the server says this person is on.
    private func adopt(_ memberships: [MembershipDTO], in context: ModelContext) {
        for membership in memberships where membership.deletedAt == nil {
            _ = upsert(membership.baby, in: context)
        }
        try? context.save()
    }

    private func upsert(_ dto: BabyDTO, in context: ModelContext) -> Baby {
        let baby = BabyStore.baby(withID: dto.id, in: context) ?? {
            let fresh = Baby(uuid: dto.id, name: dto.name, birthDate: dto.birthDate)
            context.insert(fresh)
            return fresh
        }()
        if !baby.needsUpload || dto.updatedAt >= baby.updatedAt {
            dto.apply(to: baby)
            BabyStore.mirrorToDefaults(baby)
        }
        baby.isShared = true
        try? context.save()
        return baby
    }

    // MARK: Sharing

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

    /// For Share: connect if need be, make sure the baby is on the server,
    /// and get an invite for it.
    func invite(for baby: Baby) async throws -> SyncClient.Invite {
        guard let container else { throw SyncError.notConfigured }
        try await ensureConnected(.share)
        share([baby], in: container.mainContext)
        await syncNow()
        guard let client else { throw SyncError.notConfigured }
        return try await client.createInvite(babyID: baby.uuid)
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

    /// Unpairs this phone. The log stays; only the link to the server goes,
    /// and it stays gone until the parent asks for it back.
    func unpair(context: ModelContext) async {
        await serial.runQuietly {
            SyncCredentials.clear()
            SyncCredentials.optedOut = true
            for baby in BabyStore.allBabies(in: context) {
                baby.isShared = false
                baby.ownerUserID = nil
            }
            try? context.save()
            self.members = []
            self.lastSyncDateValue = nil
            self.phraseState = .unknown
            self.status = .localOnly
        }
    }

    // MARK: The recovery phrase

    /// This parent's phrase, if this phone holds it.
    var recoveryPhrase: String? { RecoveryPhrase.current(userID: SyncCredentials.userID) }

    /// Before this phone forgets who it was (a reset server, a lost token):
    /// keep this parent's phrase as the one to set up with again, so the copy
    /// on paper still works rather than being quietly replaced by a new one.
    private func carryPhraseForward() {
        guard let phrase = recoveryPhrase,
              RecoveryPhrase.stored(account: RecoveryPhrase.pendingAccount) == nil else { return }
        RecoveryPhrase.store(phrase, account: RecoveryPhrase.pendingAccount)
    }

    /// Makes the phrase for a parent adding their first baby, before the phone
    /// has connected, so it can be written down straight away.
    @discardableResult
    func preparePhrase() -> String { RecoveryPhrase.pendingOrNew() }

    /// Asks the server whether the phrase here is the one it knows.
    func refreshPhraseState() async {
        guard let client else { return }
        guard let phrase = recoveryPhrase else {
            let account = try? await client.me()
            phraseState = account?.recoveryKey?.exists == true ? .notOnThisPhone : .unknown
            return
        }
        guard let check = try? await client.checkRecoveryPhrase(RecoveryKey.hash(phrase)) else { return }
        phraseState = check.matches ? .matches : (check.exists ? .differs : .notRegistered)
    }

    private func updatePhraseState(serverHasPhrase: Bool) {
        if !serverHasPhrase {
            phraseState = recoveryPhrase == nil ? .unknown : .notRegistered
        } else if phraseState == .unknown, recoveryPhrase == nil {
            phraseState = .notOnThisPhone
        }
    }

    /// For a phone paired before phrases existed: makes one and registers it.
    /// Never replaces one the server already has; that's `replacePhrase`.
    @discardableResult
    func registerPhrase() async throws -> String {
        guard let client, let userID = SyncCredentials.userID else { throw SyncError.notConfigured }
        let phrase = recoveryPhrase ?? RecoveryKey.generate()
        try await client.setRecoveryPhraseHash(RecoveryKey.hash(phrase))
        RecoveryPhrase.store(phrase, account: RecoveryPhrase.account(for: userID))
        RecoveryPhrase.forget(account: RecoveryPhrase.pendingAccount)
        phraseState = .matches
        return phrase
    }

    /// A new phrase, retiring the old one straight away. Only ever on request.
    func replacePhrase() async throws -> String {
        guard let client, let userID = SyncCredentials.userID else { throw SyncError.notConfigured }
        let phrase = RecoveryKey.generate()
        try await client.setRecoveryPhraseHash(RecoveryKey.hash(phrase), replace: true)
        RecoveryPhrase.store(phrase, account: RecoveryPhrase.account(for: userID))
        phraseState = .matches
        return phrase
    }

    // MARK: Helpers

    private static var deviceName: String {
        #if canImport(UIKit)
        return UIDevice.current.name
        #else
        return "iPhone"
        #endif
    }

    private func sharedBabies(in context: ModelContext) -> [Baby] {
        fetch(Baby.self, in: context).filter(\.isShared)
    }

    private func fetch<T: PersistentModel>(_ type: T.Type, in context: ModelContext) -> [T] {
        (try? context.fetch(FetchDescriptor<T>())) ?? []
    }

    /// Rows waiting to go up, for "3 changes waiting".
    func pendingCount(in context: ModelContext) -> Int {
        func count<T: PersistentModel>(_ predicate: Predicate<T>) -> Int {
            (try? context.fetchCount(FetchDescriptor<T>(predicate: predicate))) ?? 0
        }
        return count(#Predicate<FeedEntry> { $0.needsUpload })
            + count(#Predicate<DiaperEntry> { $0.needsUpload })
            + count(#Predicate<WeightEntry> { $0.needsUpload })
            + count(#Predicate<CareNote> { $0.needsUpload })
            + count(#Predicate<SolidFoodEntry> { $0.needsUpload })
    }

    private func queueEverything(for babyID: UUID, in context: ModelContext) {
        for feed in fetch(FeedEntry.self, in: context) where feed.babyID == babyID { feed.needsUpload = true }
        for weight in fetch(WeightEntry.self, in: context) where weight.babyID == babyID { weight.needsUpload = true }
        for note in fetch(CareNote.self, in: context) where note.babyID == babyID { note.needsUpload = true }
        for diaper in fetch(DiaperEntry.self, in: context) where diaper.babyID == babyID { diaper.needsUpload = true }
        for food in fetch(SolidFoodEntry.self, in: context) where food.babyID == babyID { food.needsUpload = true }
    }

    /// For a server that lost its database: every shared baby goes back up in
    /// full, and every pull starts from the beginning.
    private func requeueEverything(in context: ModelContext) {
        for baby in BabyStore.allBabies(in: context) where baby.isShared {
            baby.needsUpload = true
            queueEverything(for: baby.uuid, in: context)
        }
        UserDefaults.standard.removeObject(forKey: Self.watermarkKey)
        try? context.save()
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

/// Runs async work one piece at a time, in the order it was asked for.
@MainActor
final class SerialWork {
    private var tail: Task<Void, Never>?

    func run<T>(_ work: @escaping @MainActor () async throws -> T) async throws -> T {
        let previous = tail
        let task = Task { @MainActor () async throws -> T in
            await previous?.value
            return try await work()
        }
        tail = Task { _ = try? await task.value }
        return try await task.value
    }

    func runQuietly(_ work: @escaping @MainActor () async -> Void) async {
        _ = try? await run { await work() }
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
extension SolidFoodDTO: SyncRow {}

protocol SyncableRow: AnyObject {
    var updatedAt: Date { get }
    var needsUpload: Bool { get set }
}

extension FeedEntry: SyncableRow {}
extension WeightEntry: SyncableRow {}
extension CareNote: SyncableRow {}
extension DiaperEntry: SyncableRow {}
extension SolidFoodEntry: SyncableRow {}

enum SyncError: LocalizedError, Equatable {
    case notConfigured
    case unpaired
    case badServerURL
    /// Not on the home Wi‑Fi, or the Mac mini is off: a calm state, not a
    /// failure. Everything stays queued and goes up when the phone is home.
    case away
    case unreachable(String)
    case server(status: Int, message: String, code: String?)
    case badResponse(String)
    case rejected(count: Int, reason: String)
    case badRecoveryKey
    /// The server answered, but it's from before sharing without credentials.
    case serverNeedsUpdate

    var errorDescription: String? {
        switch self {
        case .notConfigured:
            "There's no sync server set up for this build, so everything stays on this iPhone."
        case .unpaired:
            "This phone isn't paired with the server."
        case .badServerURL:
            "That server address doesn't look right."
        case .away:
            "Can't reach your Mac mini. Connect to your home Wi‑Fi and try again."
        case .unreachable(let detail):
            "Couldn't reach the server. \(detail)"
        case .server(_, let message, _):
            message
        case .badResponse:
            "The server sent something this version of the app didn't understand."
        case .rejected(let count, let reason):
            "The server wouldn't accept \(count == 1 ? "a row" : "\(count) rows"): \(reason)"
        case .badRecoveryKey:
            "A recovery phrase is \(RecoveryKey.length) letters and numbers. Check for a missed character."
        case .serverNeedsUpdate:
            "Your Mac mini's Baby Feed server needs an update before phones can share without a code."
        }
    }

    /// The server's own code, for the errors that have one.
    var code: String? {
        if case .server(_, _, let code) = self { return code }
        return nil
    }

    /// A transport failure, sorted into "not at home" (the everyday case, which
    /// the app treats calmly) and anything else.
    static func classify(_ error: Error) -> SyncError {
        if let error = error as? SyncError { return error }
        if let urlError = error as? URLError {
            switch urlError.code {
            case .cannotFindHost, .cannotConnectToHost, .timedOut, .notConnectedToInternet,
                 .networkConnectionLost, .dnsLookupFailed, .internationalRoamingOff, .dataNotAllowed:
                return .away
            default:
                return .unreachable(urlError.localizedDescription)
            }
        }
        return .unreachable(error.localizedDescription)
    }
}
