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

    private func send<T: Decodable>(_ request: URLRequest, as type: T.Type) async throws -> T {
        let (data, response): (Data, URLResponse)
        do {
            (data, response) = try await Self.session.data(for: request)
        } catch {
            throw SyncError.unreachable(error.localizedDescription)
        }
        guard let http = response as? HTTPURLResponse else { throw SyncError.unreachable("No response") }

        guard (200..<300).contains(http.statusCode) else {
            let failure = try? Self.decoder.decode(ServerError.self, from: data)
            if http.statusCode == 401 { throw SyncError.unpaired }
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
    }

    /// Checks an address is a Baby Feed server before saving it, so a typo
    /// fails on the setup screen rather than silently never syncing.
    func health() async throws -> Health {
        try await send(try request("GET", "/v1/health"), as: Health.self)
    }

    struct Pairing: Decodable {
        let token: String
        let userID: UUID
        let displayName: String
        let baby: BabyDTO?

        enum CodingKeys: String, CodingKey {
            case token, baby
            case userID = "user_id"
            case displayName = "display_name"
        }
    }

    /// The first phone, with the setup code from the Mac mini.
    func claim(secret: String, displayName: String, deviceName: String) async throws -> Pairing {
        let body = try Self.encoder.encode([
            "secret": secret, "display_name": displayName, "device_name": deviceName,
        ])
        return try await send(try request("POST", "/v1/pair/claim", body: body), as: Pairing.self)
    }

    /// Every phone after the first, with a code from the first one.
    func join(code: String, displayName: String, deviceName: String) async throws -> Pairing {
        let body = try Self.encoder.encode([
            "code": code, "display_name": displayName, "device_name": deviceName,
        ])
        return try await send(try request("POST", "/v1/pair/invite", body: body), as: Pairing.self)
    }

    struct RecoveryStatus: Decodable {
        let exists: Bool
        let createdAt: Date?

        enum CodingKeys: String, CodingKey {
            case exists
            case createdAt = "created_at"
        }
    }

    /// Registers the hash of a key this phone made. The key itself never
    /// leaves the phone, which is the whole point of the arrangement.
    func setRecoveryKeyHash(_ hash: String, babyID: UUID) async throws {
        struct Response: Decodable { let babyID: UUID; enum CodingKeys: String, CodingKey { case babyID = "baby_id" } }
        let body = try Self.encoder.encode(["key_hash": hash])
        _ = try await send(try request("POST", "/v1/babies/\(babyID.uuidString)/recovery", body: body),
                           as: Response.self)
    }

    func recoveryStatus(babyID: UUID) async throws -> RecoveryStatus {
        try await send(try request("GET", "/v1/babies/\(babyID.uuidString)/recovery"), as: RecoveryStatus.self)
    }

    /// Redeems a key. Sent without a token on a phone that has nothing, and
    /// with one when adding a recovered log to the caregiver this phone
    /// already is — the server decides which from the header.
    func recover(key: String, displayName: String, deviceName: String) async throws -> Pairing {
        let body = try Self.encoder.encode([
            "key": RecoveryKey.normalized(key),
            "display_name": displayName,
            "device_name": deviceName,
        ])
        return try await send(try request("POST", "/v1/recover", body: body), as: Pairing.self)
    }

    struct Account: Decodable {
        let userID: UUID
        let displayName: String
        let babies: [MembershipDTO]

        enum CodingKeys: String, CodingKey {
            case babies
            case userID = "user_id"
            case displayName = "display_name"
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

    func createInvite(babyID: UUID, expiresInMinutes: Int = 60) async throws -> Invite {
        let body = try Self.encoder.encode(["expires_in_minutes": expiresInMinutes])
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
