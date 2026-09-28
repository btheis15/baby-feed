import Foundation

/// The transport. One `URLSession`, the endpoints the Mac mini serves, and
/// nothing else — no merge decisions, no SwiftData. `SyncEngine` owns those.
///
/// Every request carries the device token. There is no refresh, no expiry and
/// no sign-in screen: the token is issued once when the phone pairs and stays
/// valid until it's revoked from the server or from Settings.
struct SyncClient: Sendable {
    let baseURL: URL
    let token: String?

    // MARK: Dates
    //
    // The server writes JavaScript's toISOString(), which always has
    // milliseconds: "2026-09-18T14:40:45.644Z". Swift's .iso8601 strategy
    // rejects fractional seconds outright, so both formats are tried. Getting
    // this wrong doesn't fail loudly — it fails as "every row is malformed",
    // which is why it's handled here once rather than per call site.

    private static let withFraction: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    private static let plain: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()

    static func parseDate(_ text: String) -> Date? {
        withFraction.date(from: text) ?? plain.date(from: text)
    }

    static func string(from date: Date) -> String { withFraction.string(from: date) }

    static var decoder: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let text = try decoder.singleValueContainer().decode(String.self)
            guard let date = parseDate(text) else {
                throw DecodingError.dataCorrupted(
                    .init(codingPath: decoder.codingPath, debugDescription: "Not a date: \(text)"))
            }
            return date
        }
        return decoder
    }

    static var encoder: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .custom { date, encoder in
            var container = encoder.singleValueContainer()
            try container.encode(string(from: date))
        }
        return encoder
    }

    private static let session: URLSession = {
        let config = URLSessionConfiguration.default
        // A feed logged at 3 a.m. should not leave the app spinning because the
        // house internet is having a moment; the push is retried on the next
        // change or the next foreground anyway.
        config.timeoutIntervalForRequest = 20
        config.timeoutIntervalForResource = 60
        config.waitsForConnectivity = false
        return URLSession(configuration: config)
    }()

    /// For "is the Mac mini there?". Away from home the answer is no, and it
    /// should come back in seconds, not after the usual twenty.
    private static let probeSession: URLSession = {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 4
        config.timeoutIntervalForResource = 6
        config.waitsForConnectivity = false
        return URLSession(configuration: config)
    }()

    // MARK: Requests

    private func request(_ method: String, _ path: String, query: [URLQueryItem] = [], body: Data? = nil) throws -> URLRequest {
        guard var components = URLComponents(url: baseURL.appendingPathComponent(path), resolvingAgainstBaseURL: false) else {
            throw SyncError.badServerURL
        }
        if !query.isEmpty { components.queryItems = query }
        guard let url = components.url else { throw SyncError.badServerURL }
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.httpBody = body
        if body != nil { request.setValue("application/json", forHTTPHeaderField: "Content-Type") }
        if let token { request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization") }
        return request
    }

    /// - Parameter authenticated: whether a 401 means this phone's token is no
    ///   good. On the pairing routes it doesn't: a wrong invite code or setup
    ///   code is a 401 too, and "this phone isn't paired" is the wrong thing to
    ///   say about a typo.
    private func send<T: Decodable>(
        _ request: URLRequest,
        as type: T.Type,
        authenticated: Bool = true,
        session: URLSession = SyncClient.session
    ) async throws -> T {
        let (data, response): (Data, URLResponse)
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            throw SyncError.classify(error)
        }
        guard let http = response as? HTTPURLResponse else { throw SyncError.unreachable("No response") }

        guard (200..<300).contains(http.statusCode) else {
            let failure = try? Self.decoder.decode(ServerError.self, from: data)
            if http.statusCode == 401, authenticated { throw SyncError.unpaired }
            throw SyncError.server(status: http.statusCode,
                                   message: failure?.error ?? "The server returned \(http.statusCode).",
                                   code: failure?.code)
        }
        do {
            return try Self.decoder.decode(T.self, from: data)
        } catch {
            throw SyncError.badResponse(String(describing: error))
        }
    }

    private struct ServerError: Decodable {
        let error: String
        let code: String?
    }

    // MARK: Endpoints

    struct Health: Decodable {
        let ok: Bool
        let service: String
        /// 2 and up: enrolment, joining as the caregiver you already are, and
        /// one recovery phrase per person. Nil on servers from before that.
        let api: Int?
        /// A random id the server keeps in its database. A different one means
        /// the database was reset, and everything has to be sent again.
        let serverID: String?
        let features: [String]
        let enroll: String?
        /// Whether a new phone could set itself up from where it's asking:
        /// false away from home, which is the usual reason sharing can't start.
        let enrollAvailable: Bool?

        enum CodingKeys: String, CodingKey {
            case ok, service, api, features, enroll
            case serverID = "server_id"
            case enrollAvailable = "enroll_available"
        }

        init(ok: Bool, service: String, api: Int?, serverID: String?, features: [String], enroll: String?, enrollAvailable: Bool?) {
            self.ok = ok
            self.service = service
            self.api = api
            self.serverID = serverID
            self.features = features
            self.enroll = enroll
            self.enrollAvailable = enrollAvailable
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            ok = try container.decode(Bool.self, forKey: .ok)
            service = try container.decode(String.self, forKey: .service)
            api = try container.decodeIfPresent(Int.self, forKey: .api)
            serverID = try container.decodeIfPresent(String.self, forKey: .serverID)
            features = try container.decodeIfPresent([String].self, forKey: .features) ?? []
            enroll = try container.decodeIfPresent(String.self, forKey: .enroll)
            enrollAvailable = try container.decodeIfPresent(Bool.self, forKey: .enrollAvailable)
        }

        func supports(_ feature: String) -> Bool { features.contains(feature) }
    }

    /// Checks an address is a Baby Feed server before saving it, so a typo
    /// fails on the setup screen rather than silently never syncing.
    func health() async throws -> Health {
        try await send(try request("GET", "/v1/health"), as: Health.self, authenticated: false)
    }

    /// The same, but quick to give up: for deciding whether we're at home.
    func probe() async throws -> Health {
        try await send(try request("GET", "/v1/health"), as: Health.self, authenticated: false,
                       session: Self.probeSession)
    }

    struct Pairing: Decodable {
        /// Nil when the phone keeps the token it already has: joining or
        /// restoring as the caregiver this phone already is.
        let token: String?
        let userID: UUID
        let displayName: String
        /// The log just joined, for a join.
        let baby: BabyDTO?
        /// Every log this caregiver is on now.
        let babies: [MembershipDTO]
        let serverID: String?
        /// Only in the answer to a personal recovery phrase (as opposed to an
        /// older per-baby key): whether this phone's previous identity was
        /// folded into the person whose phrase it was.
        let merged: Bool?

        var wasPersonalPhrase: Bool { merged != nil }

        enum CodingKeys: String, CodingKey {
            case token, baby, babies, merged
            case userID = "user_id"
            case displayName = "display_name"
            case serverID = "server_id"
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            token = try container.decodeIfPresent(String.self, forKey: .token)
            userID = try container.decode(UUID.self, forKey: .userID)
            displayName = try container.decodeIfPresent(String.self, forKey: .displayName) ?? ""
            baby = try container.decodeIfPresent(BabyDTO.self, forKey: .baby)
            babies = try container.decodeIfPresent([MembershipDTO].self, forKey: .babies) ?? []
            serverID = try container.decodeIfPresent(String.self, forKey: .serverID)
            merged = try container.decodeIfPresent(Bool.self, forKey: .merged)
        }
    }

    /// A new phone on the home Wi‑Fi, setting itself up with nothing typed.
    /// The recovery phrase's hash rides along, so a phone is never set up
    /// without one.
    func enroll(displayName: String, deviceName: String, keyHash: String?) async throws -> Pairing {
        var fields = ["display_name": displayName, "device_name": deviceName]
        if let keyHash { fields["key_hash"] = keyHash }
        let body = try Self.encoder.encode(fields)
        return try await send(try request("POST", "/v1/pair/enroll", body: body), as: Pairing.self,
                              authenticated: false)
    }

    /// Joins a log from an invite. Sent with this phone's token (when the
    /// client has one), it joins as the caregiver this phone already is.
    func join(code: String, displayName: String, deviceName: String) async throws -> Pairing {
        let body = try Self.encoder.encode([
            "code": code, "display_name": displayName, "device_name": deviceName,
        ])
        return try await send(try request("POST", "/v1/pair/invite", body: body), as: Pairing.self,
                              authenticated: false)
    }

    struct RecoveryStatus: Decodable, Equatable {
        let exists: Bool
        let createdAt: Date?

        enum CodingKeys: String, CodingKey {
            case exists
            case createdAt = "created_at"
        }
    }

    struct PhraseCheck: Decodable, Equatable {
        let exists: Bool
        let matches: Bool
    }

    /// Registers this person's recovery phrase, by its hash; the phrase itself
    /// never leaves the phone. Refused (409 `key_exists`) when a different one
    /// is already set, unless `replace` says to retire it.
    func setRecoveryPhraseHash(_ hash: String, replace: Bool = false) async throws {
        struct Body: Encodable {
            let key_hash: String
            let replace: Bool
        }
        _ = try await send(try request("POST", "/v1/me/recovery", body: try Self.encoder.encode(Body(key_hash: hash, replace: replace))),
                           as: RecoveryStatus.self)
    }

    /// Whether the phrase on this phone is the one the server knows.
    func checkRecoveryPhrase(_ hash: String) async throws -> PhraseCheck {
        let body = try Self.encoder.encode(["key_hash": hash])
        return try await send(try request("POST", "/v1/me/recovery/check", body: body), as: PhraseCheck.self)
    }

    /// Redeems a phrase (or an older per-baby key). Sent without a token on a
    /// phone that has nothing, and with one on a phone that's already paired,
    /// which the server folds into the person the phrase belongs to.
    func recover(key: String, displayName: String, deviceName: String) async throws -> Pairing {
        let body = try Self.encoder.encode([
            "key": RecoveryKey.normalized(key),
            "display_name": displayName,
            "device_name": deviceName,
        ])
        return try await send(try request("POST", "/v1/recover", body: body), as: Pairing.self,
                              authenticated: false)
    }

    struct Account: Decodable {
        let userID: UUID
        let displayName: String
        let babies: [MembershipDTO]
        let recoveryKey: RecoveryStatus?
        let serverID: String?

        enum CodingKeys: String, CodingKey {
            case babies
            case userID = "user_id"
            case displayName = "display_name"
            case recoveryKey = "recovery_key"
            case serverID = "server_id"
        }
    }

    func me() async throws -> Account {
        try await send(try request("GET", "/v1/me"), as: Account.self)
    }

    func setDisplayName(_ name: String) async throws {
        let body = try Self.encoder.encode(["display_name": name])
        _ = try await send(try request("POST", "/v1/me", body: body), as: Account.Name.self)
    }

    struct Invite: Decodable {
        let code: String
        let babyID: UUID
        let expiresAt: Date

        enum CodingKeys: String, CodingKey {
            case code
            case babyID = "baby_id"
            case expiresAt = "expires_at"
        }
    }

    /// A day and ten phones by default: long enough to hand round the family
    /// that evening, short enough that an old screenshot stops working.
    func createInvite(babyID: UUID, expiresInMinutes: Int = 1440, maxUses: Int = 10) async throws -> Invite {
        let body = try Self.encoder.encode(["expires_in_minutes": expiresInMinutes, "max_uses": maxUses])
        return try await send(try request("POST", "/v1/babies/\(babyID.uuidString)/invites", body: body),
                              as: Invite.self)
    }

    private struct MembersResponse: Decodable { let members: [MemberDTO] }

    func members(babyID: UUID) async throws -> [MemberDTO] {
        try await send(try request("GET", "/v1/babies/\(babyID.uuidString)/members"),
                       as: MembersResponse.self).members
    }

    private struct RemovalResponse: Decodable { let removed: String }

    func removeMember(babyID: UUID, userID: UUID) async throws {
        _ = try await send(
            try request("DELETE", "/v1/babies/\(babyID.uuidString)/members/\(userID.uuidString)"),
            as: RemovalResponse.self)
    }

    struct PushResult: Decodable {
        struct Applied: Decodable {
            let table: String
            let id: UUID
            let status: String
        }
        struct Rejected: Decodable {
            let table: String
            let id: UUID?
            let reason: String
            /// `malformed`, or `not_a_member` for a log this caregiver was
            /// taken off. Nil from servers that don't say.
            let code: String?
        }
        let applied: [Applied]
        let rejected: [Rejected]
    }

    func push(_ payload: SyncPushPayload) async throws -> PushResult {
        let body = try Self.encoder.encode(payload)
        return try await send(try request("POST", "/v1/sync/push", body: body), as: PushResult.self)
    }

    struct PullResult: Decodable {
        let babies: [BabyDTO]
        let feeds: [FeedDTO]
        let weights: [WeightDTO]
        let careNotes: [CareNoteDTO]
        let diapers: [DiaperDTO]
        let solidFoods: [SolidFoodDTO]
        let members: [MemberDTO]
        let hasMore: Bool

        enum CodingKeys: String, CodingKey {
            case babies, feeds, weights, diapers, members
            case careNotes = "care_notes"
            case solidFoods = "solid_foods"
            case hasMore = "has_more"
        }

        // A server from before diapers or solid foods existed omits those
        // keys; that's an older deployment, not an error, and everything else
        // should still sync.
        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            babies = try container.decode([BabyDTO].self, forKey: .babies)
            feeds = try container.decode([FeedDTO].self, forKey: .feeds)
            weights = try container.decode([WeightDTO].self, forKey: .weights)
            careNotes = try container.decode([CareNoteDTO].self, forKey: .careNotes)
            diapers = try container.decodeIfPresent([DiaperDTO].self, forKey: .diapers) ?? []
            solidFoods = try container.decodeIfPresent([SolidFoodDTO].self, forKey: .solidFoods) ?? []
            members = try container.decode([MemberDTO].self, forKey: .members)
            hasMore = try container.decode(Bool.self, forKey: .hasMore)
        }

        /// Every server timestamp in this response, for the next watermark.
        var serverStamps: [Date] {
            babies.compactMap(\.serverUpdatedAt) + feeds.compactMap(\.serverUpdatedAt)
                + weights.compactMap(\.serverUpdatedAt) + careNotes.compactMap(\.serverUpdatedAt)
                + diapers.compactMap(\.serverUpdatedAt) + solidFoods.compactMap(\.serverUpdatedAt)
        }

        var isEmpty: Bool {
            babies.isEmpty && feeds.isEmpty && weights.isEmpty && careNotes.isEmpty
                && diapers.isEmpty && solidFoods.isEmpty
        }
    }

    func pull(babyID: UUID, since: Date?) async throws -> PullResult {
        var query = [URLQueryItem(name: "baby_id", value: babyID.uuidString)]
        if let since { query.append(URLQueryItem(name: "since", value: Self.string(from: since))) }
        return try await send(try request("GET", "/v1/sync/pull", query: query), as: PullResult.self)
    }
}

extension SyncClient.Account {
    struct Name: Decodable {
        let displayName: String
        enum CodingKeys: String, CodingKey { case displayName = "display_name" }
    }
}

/// What a push sends. Empty lists are omitted so a sync with one new feed is
/// one small request, which matters on a phone that's on cellular all day.
struct SyncPushPayload: Encodable {
    var babies: [BabyDTO]?
    var feeds: [FeedDTO]?
    var weights: [WeightDTO]?
    var careNotes: [CareNoteDTO]?
    var diapers: [DiaperDTO]?
    var solidFoods: [SolidFoodDTO]?

    enum CodingKeys: String, CodingKey {
        case babies, feeds, weights, diapers
        case careNotes = "care_notes"
        case solidFoods = "solid_foods"
    }

    var isEmpty: Bool {
        (babies?.isEmpty ?? true) && (feeds?.isEmpty ?? true)
            && (weights?.isEmpty ?? true) && (careNotes?.isEmpty ?? true)
            && (diapers?.isEmpty ?? true) && (solidFoods?.isEmpty ?? true)
    }
}
