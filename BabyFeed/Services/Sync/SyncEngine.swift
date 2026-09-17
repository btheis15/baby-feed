import Foundation
import Observation
import Supabase
import SwiftData

/// Offline-first sync with Supabase. The local SwiftData store is the source
/// of truth; this pushes rows flagged `needsUpload`, pulls rows changed on the
/// server since the last pull, and listens for realtime changes.
@MainActor
@Observable
final class SyncEngine {
    static let shared = SyncEngine()

    enum Status: Equatable {
        case notConfigured
        case signedOut
        case idle(lastSync: Date?)
        case syncing
        case error(String)
    }

    private(set) var status: Status
    private(set) var userID: UUID?
    private(set) var userEmail: String?
    /// Caregivers of the current baby, refreshed on each pull.
    private(set) var members: [MemberDTO] = []

    let client: SupabaseClient?

    private var container: ModelContainer?
    private var authTask: Task<Void, Never>?
    private var realtimeTasks: [Task<Void, Never>] = []
    private var syncTask: Task<Void, Never>?
    private var syncRequestedWhileRunning = false

    private static let watermarkKey = "sync.watermarks"
    private static let lastSyncKey = "sync.lastSync"

    private init() {
        if SupabaseConfig.isConfigured {
            client = SupabaseClient(supabaseURL: SupabaseConfig.url, supabaseKey: SupabaseConfig.anonKey)
            status = .signedOut
        } else {
            client = nil
            status = .notConfigured
        }
    }

    var isConfigured: Bool { client != nil }
    var isSignedIn: Bool { userID != nil }

    var lastSyncDate: Date? {
        let interval = UserDefaults.standard.double(forKey: Self.lastSyncKey)
        return interval > 0 ? Date(timeIntervalSince1970: interval) : nil
    }

    // MARK: Lifecycle

    func start(container: ModelContainer) {
        self.container = container
        guard let client, authTask == nil else { return }
        authTask = Task { [weak self] in
            for await (_, session) in client.auth.authStateChanges {
                await self?.sessionChanged(session)
            }
        }
    }

    private func sessionChanged(_ session: Session?) async {
        userID = session?.user.id
        userEmail = session?.user.email
        if session != nil {
            if AppSettings.displayName.isEmpty {
                AppSettings.displayName = SyncMerge.suggestedDisplayName(givenName: nil, familyName: nil, email: userEmail)
            }
            status = .idle(lastSync: lastSyncDate)
            requestSync()
            await startRealtime()
        } else {
            status = .signedOut
            members = []
            stopRealtime()
        }
    }

    // MARK: Auth

    func signInWithApple(idToken: String, nonce: String, givenName: String?, familyName: String?) async throws {
        guard let client else { throw SyncError.notConfigured }
        let session = try await client.auth.signInWithIdToken(
            credentials: OpenIDConnectCredentials(provider: .apple, idToken: idToken, nonce: nonce)
        )
        if AppSettings.displayName.isEmpty {
            AppSettings.displayName = SyncMerge.suggestedDisplayName(givenName: givenName, familyName: familyName, email: session.user.email)
        }
    }

    func sendEmailCode(to email: String) async throws {
        guard let client else { throw SyncError.notConfigured }
        try await client.auth.signInWithOTP(email: email)
    }

    func verifyEmailCode(email: String, code: String) async throws {
        guard let client else { throw SyncError.notConfigured }
        try await client.auth.verifyOTP(email: email, token: code, type: .email)
    }

    func signOut() async {
        guard let client else { return }
        try? await client.auth.signOut()
    }

    // MARK: Sharing

    /// Uploads the baby and its history so other caregivers can join. Returns an invite code.
    func share(_ baby: Baby, in context: ModelContext) async throws -> String {
        guard let client, let userID else { throw SyncError.signedOut }
        baby.isShared = true
        baby.ownerUserID = userID.uuidString
        baby.markChanged()

        let id = baby.uuid
        let feeds = (try? context.fetch(FetchDescriptor<FeedEntry>(predicate: #Predicate { $0.babyID == id }))) ?? []
        feeds.forEach { $0.needsUpload = true }
        let weights = (try? context.fetch(FetchDescriptor<WeightEntry>(predicate: #Predicate { $0.babyID == id }))) ?? []
        weights.forEach { $0.needsUpload = true }
        try context.save()

        try await client.from("babies").upsert(BabyDTO(baby: baby, createdBy: userID)).execute()
        baby.needsUpload = false
        try context.save()
        try await updateOwnDisplayName(babyID: id)
        try await push(in: context)

        let code = try await createInvite(for: baby)
        await startRealtime()
        return code
    }

    func createInvite(for baby: Baby) async throws -> String {
        guard let client else { throw SyncError.notConfigured }
        let code: String = try await client
            .rpc("create_invite", params: ["p_baby_id": baby.uuid.uuidString])
            .execute()
            .value
        return code
    }

    /// Redeems a code, adds the baby locally, makes it current, and pulls its history.
    func join(code rawCode: String, in context: ModelContext) async throws -> Baby {
        guard let client else { throw SyncError.notConfigured }
        let code = SyncMerge.normalizedInviteCode(rawCode)
        guard SyncMerge.isPlausibleInviteCode(code) else { throw SyncError.badCode }

        let rows: [BabyDTO] = try await client
            .rpc("join_baby", params: ["p_code": code, "p_display_name": AppSettings.displayName])
            .execute()
            .value
        guard let dto = rows.first else { throw SyncError.badCode }

        let baby = BabyStore.baby(withID: dto.id, in: context) ?? {
            let created = Baby(uuid: dto.id, name: dto.name, birthDate: dto.birthDate)
            context.insert(created)
            return created
        }()
        dto.apply(to: baby)
        try context.save()

        Self.setWatermark(nil, for: baby.uuid)
        BabyStore.setCurrent(baby, in: context)
        try await pull(in: context)
        await startRealtime()
        return baby
    }

    func refreshMembers(for babyID: UUID) async {
        guard let client else { return }
        let rows: [MemberDTO]? = try? await client
            .from("baby_members")
            .select()
            .eq("baby_id", value: babyID.uuidString)
            .order("joined_at")
            .execute()
            .value
        if let rows { members = rows }
    }

    func updateOwnDisplayName(babyID: UUID) async throws {
        guard let client, let userID else { return }
        try await client
            .from("baby_members")
            .update(["display_name": AppSettings.displayName])
            .eq("baby_id", value: babyID.uuidString)
            .eq("user_id", value: userID.uuidString)
            .execute()
        await refreshMembers(for: babyID)
    }

    func removeMember(_ member: MemberDTO) async throws {
        guard let client else { throw SyncError.notConfigured }
        try await client
            .from("baby_members")
            .delete()
            .eq("baby_id", value: member.babyID.uuidString)
            .eq("user_id", value: member.userID.uuidString)
            .execute()
        await refreshMembers(for: member.babyID)
    }

    /// Stop following a shared baby. Removes the membership and the local copy.
    func leave(_ baby: Baby, in context: ModelContext) async throws {
        guard let client, let userID else { throw SyncError.signedOut }
        try await client
            .from("baby_members")
            .delete()
            .eq("baby_id", value: baby.uuid.uuidString)
            .eq("user_id", value: userID.uuidString)
            .execute()
        Self.setWatermark(nil, for: baby.uuid)
        BabyStore.removeLocally(baby, in: context)
        await startRealtime()
    }

    // MARK: Sync

    /// Coalesces bursts of changes into one sync run.
    func requestSync() {
        guard isSignedIn, container != nil else { return }
        if syncTask != nil {
            syncRequestedWhileRunning = true
            return
        }
        syncTask = Task { [weak self] in
            guard let self else { return }
            repeat {
                self.syncRequestedWhileRunning = false
                await self.syncNow()
            } while self.syncRequestedWhileRunning
            self.syncTask = nil
        }
    }

    func syncNow() async {
        guard let container, isSignedIn else { return }
        let context = container.mainContext
        status = .syncing
        do {
            try await push(in: context)
            try await pull(in: context)
            UserDefaults.standard.set(Date.now.timeIntervalSince1970, forKey: Self.lastSyncKey)
            status = .idle(lastSync: lastSyncDate)
        } catch {
            status = .error(error.localizedDescription)
        }
    }

    private func sharedBabies(in context: ModelContext) -> [Baby] {
        let babies = (try? context.fetch(FetchDescriptor<Baby>(predicate: #Predicate { $0.isShared == true }))) ?? []
        return babies.filter { $0.deletedAt == nil }
    }

    private func push(in context: ModelContext) async throws {
        guard let client, let userID else { return }
        let babies = sharedBabies(in: context)
        let sharedIDs = Set(babies.map(\.uuid))
        guard !sharedIDs.isEmpty else { return }

        for baby in babies where baby.needsUpload {
            try await client.from("babies").upsert(BabyDTO(baby: baby, createdBy: UUID(uuidString: baby.ownerUserID ?? "") ?? userID)).execute()
            baby.needsUpload = false
        }

        let feeds = (try? context.fetch(FetchDescriptor<FeedEntry>(predicate: #Predicate { $0.needsUpload == true }))) ?? []
        let feedDTOs = feeds
            .filter { $0.babyID.map(sharedIDs.contains) ?? false }
            .compactMap { FeedDTO(entry: $0, userID: userID) }
        if !feedDTOs.isEmpty {
            try await client.from("feeds").upsert(feedDTOs).execute()
            let pushed = Set(feedDTOs.map(\.id))
            feeds.filter { $0.uuid.map(pushed.contains) ?? false }.forEach { $0.needsUpload = false }
        }

        let weights = (try? context.fetch(FetchDescriptor<WeightEntry>(predicate: #Predicate { $0.needsUpload == true }))) ?? []
        let weightDTOs = weights
            .filter { $0.babyID.map(sharedIDs.contains) ?? false }
            .compactMap { WeightDTO(entry: $0, userID: userID) }
        if !weightDTOs.isEmpty {
            try await client.from("weights").upsert(weightDTOs).execute()
            let pushed = Set(weightDTOs.map(\.id))
            weights.filter { $0.uuid.map(pushed.contains) ?? false }.forEach { $0.needsUpload = false }
        }

        try context.save()
    }

    private func pull(in context: ModelContext) async throws {
        guard let client else { return }
        var changed = false

        for baby in sharedBabies(in: context) {
            let babyID = baby.uuid
            let since = Self.watermark(for: babyID)
            var seen: [Date] = []

            // The baby itself (name, birthday).
            let babyRows: [BabyDTO] = try await client
                .from("babies")
                .select()
                .eq("id", value: babyID.uuidString)
                .execute()
                .value
            if let remote = babyRows.first,
               SyncMerge.remoteWins(remoteUpdatedAt: remote.updatedAt, localUpdatedAt: baby.updatedAt, localNeedsUpload: baby.needsUpload) {
                remote.apply(to: baby)
                BabyStore.mirrorToDefaults(baby)
                changed = true
            }

            // Feeds.
            var feedQuery = client.from("feeds").select().eq("baby_id", value: babyID.uuidString)
            if let since { feedQuery = feedQuery.gt("server_updated_at", value: Self.iso8601(since)) }
            let feedRows: [FeedDTO] = try await feedQuery.order("server_updated_at").execute().value
            for row in feedRows {
                seen.append(row.serverUpdatedAt ?? row.updatedAt)
                let rowID = row.id
                let existing = try? context.fetch(FetchDescriptor<FeedEntry>(predicate: #Predicate { $0.uuid == rowID })).first
                if let existing {
                    if SyncMerge.remoteWins(remoteUpdatedAt: row.updatedAt, localUpdatedAt: existing.updatedAt, localNeedsUpload: existing.needsUpload) {
                        row.apply(to: existing)
                        changed = true
                    }
                } else {
                    let entry = FeedEntry(uuid: row.id, babyID: row.babyID, kind: FeedKind(rawValue: row.kind) ?? .formula)
                    row.apply(to: entry)
                    context.insert(entry)
                    changed = true
                }
            }

            // Weights.
            var weightQuery = client.from("weights").select().eq("baby_id", value: babyID.uuidString)
            if let since { weightQuery = weightQuery.gt("server_updated_at", value: Self.iso8601(since)) }
            let weightRows: [WeightDTO] = try await weightQuery.order("server_updated_at").execute().value
            for row in weightRows {
                seen.append(row.serverUpdatedAt ?? row.updatedAt)
                let rowID = row.id
                let existing = try? context.fetch(FetchDescriptor<WeightEntry>(predicate: #Predicate { $0.uuid == rowID })).first
                if let existing {
                    if SyncMerge.remoteWins(remoteUpdatedAt: row.updatedAt, localUpdatedAt: existing.updatedAt, localNeedsUpload: existing.needsUpload) {
                        row.apply(to: existing)
                        changed = true
                    }
                } else {
                    let entry = WeightEntry(uuid: row.id, babyID: row.babyID, grams: row.grams)
                    row.apply(to: entry)
                    context.insert(entry)
                    changed = true
                }
            }

            Self.setWatermark(SyncMerge.nextWatermark(previous: since, seen: seen), for: babyID)

            if babyID == AppSettings.currentBabyID {
                await refreshMembers(for: babyID)
            }
        }

        if changed {
            try context.save()
            FeedCoordinator.feedsDidChange(in: context, triggerSync: false)
        }
    }

    // MARK: Realtime

    private func startRealtime() async {
        stopRealtime()
        guard let client, let container, isSignedIn else { return }
        for baby in sharedBabies(in: container.mainContext) {
            let id = baby.uuid.uuidString
            let channel = client.channel("baby-\(id)")
            let feedChanges = channel.postgresChange(AnyAction.self, schema: "public", table: "feeds", filter: "baby_id=eq.\(id)")
            let weightChanges = channel.postgresChange(AnyAction.self, schema: "public", table: "weights", filter: "baby_id=eq.\(id)")
            let babyChanges = channel.postgresChange(AnyAction.self, schema: "public", table: "babies", filter: "id=eq.\(id)")
            let memberChanges = channel.postgresChange(AnyAction.self, schema: "public", table: "baby_members", filter: "baby_id=eq.\(id)")
            try? await channel.subscribe()

            realtimeTasks.append(Task { [weak self] in
                for await _ in feedChanges { await self?.requestSync() }
            })
            realtimeTasks.append(Task { [weak self] in
                for await _ in weightChanges { await self?.requestSync() }
            })
            realtimeTasks.append(Task { [weak self] in
                for await _ in babyChanges { await self?.requestSync() }
            })
            realtimeTasks.append(Task { [weak self] in
                for await _ in memberChanges { await self?.requestSync() }
            })
            realtimeTasks.append(Task {
                // Keep the channel alive for as long as the tasks run.
                _ = channel
                while !Task.isCancelled {
                    try? await Task.sleep(for: .seconds(3600))
                }
                await channel.unsubscribe()
            })
        }
    }

    private func stopRealtime() {
        realtimeTasks.forEach { $0.cancel() }
        realtimeTasks = []
    }

    // MARK: Watermarks

    private static func watermark(for babyID: UUID) -> Date? {
        let all = UserDefaults.standard.dictionary(forKey: watermarkKey) as? [String: Double] ?? [:]
        return all[babyID.uuidString].map { Date(timeIntervalSince1970: $0) }
    }

    private static func setWatermark(_ date: Date?, for babyID: UUID) {
        var all = UserDefaults.standard.dictionary(forKey: watermarkKey) as? [String: Double] ?? [:]
        if let date {
            all[babyID.uuidString] = date.timeIntervalSince1970
        } else {
            all.removeValue(forKey: babyID.uuidString)
        }
        UserDefaults.standard.set(all, forKey: watermarkKey)
    }

    private static func iso8601(_ date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.string(from: date)
    }
}

enum SyncError: LocalizedError {
    case notConfigured
    case signedOut
    case badCode

    var errorDescription: String? {
        switch self {
        case .notConfigured: "Sync isn't set up in this build yet."
        case .signedOut: "Sign in first."
        case .badCode: "That doesn't look like a valid invite code."
        }
    }
}
