import Foundation

/// Row shapes for syncing, kept snake_case because the server that will
/// eventually consume them is a Postgres database hosted on the Mac Mini.
///
/// Nothing sends these yet – `SyncEngine` has no transport. They're here
/// because the shapes and the merge rules are the settled part of syncing; only
/// the client is missing.
struct BabyDTO: Codable, Equatable {
    var id: UUID
    var name: String
    var birthDate: Date?
    var createdBy: UUID
    var updatedAt: Date
    var deletedAt: Date?
    var serverUpdatedAt: Date?

    enum CodingKeys: String, CodingKey {
        case id, name
        case birthDate = "birth_date"
        case createdBy = "created_by"
        case updatedAt = "updated_at"
        case deletedAt = "deleted_at"
        case serverUpdatedAt = "server_updated_at"
    }

    init(baby: Baby, createdBy: UUID) {
        id = baby.uuid
        name = baby.name
        birthDate = baby.birthDate
        self.createdBy = createdBy
        updatedAt = baby.updatedAt
        deletedAt = baby.deletedAt
        serverUpdatedAt = nil
    }

    func apply(to baby: Baby) {
        baby.name = name
        baby.birthDate = birthDate
        baby.updatedAt = updatedAt
        baby.deletedAt = deletedAt
        baby.ownerUserID = createdBy.uuidString
        baby.isShared = true
        baby.needsUpload = false
    }
}

struct FeedDTO: Codable, Equatable {
    var id: UUID
    var babyID: UUID
    var startTime: Date
    var kind: String
    var amountML: Double?
    var durationMinutes: Int?
    var side: String?
    var note: String
    var loggedBy: UUID?
    var loggedByName: String
    var updatedAt: Date
    var deletedAt: Date?
    var serverUpdatedAt: Date?

    enum CodingKeys: String, CodingKey {
        case id, kind, side, note
        case babyID = "baby_id"
        case startTime = "start_time"
        case amountML = "amount_ml"
        case durationMinutes = "duration_minutes"
        case loggedBy = "logged_by"
        case loggedByName = "logged_by_name"
        case updatedAt = "updated_at"
        case deletedAt = "deleted_at"
        case serverUpdatedAt = "server_updated_at"
    }

    init?(entry: FeedEntry, userID: UUID) {
        guard let uuid = entry.uuid, let babyID = entry.babyID else { return nil }
        id = uuid
        self.babyID = babyID
        startTime = entry.startTime
        kind = entry.kindRaw
        amountML = entry.amountML
        durationMinutes = entry.durationMinutes
        side = entry.sideRaw
        note = entry.note
        loggedBy = userID
        loggedByName = entry.loggedByName
        updatedAt = entry.updatedAt
        deletedAt = entry.deletedAt
        serverUpdatedAt = nil
    }

    func apply(to entry: FeedEntry) {
        entry.uuid = id
        entry.babyID = babyID
        entry.startTime = startTime
        entry.kindRaw = kind
        entry.amountML = amountML
        entry.durationMinutes = durationMinutes
        entry.sideRaw = side
        entry.note = note
        entry.loggedByName = loggedByName
        entry.updatedAt = updatedAt
        entry.deletedAt = deletedAt
        entry.needsUpload = false
    }
}

struct WeightDTO: Codable, Equatable {
    var id: UUID
    var babyID: UUID
    var date: Date
    var grams: Double
    var note: String
    var loggedBy: UUID?
    var loggedByName: String
    var updatedAt: Date
    var deletedAt: Date?
    var serverUpdatedAt: Date?

    enum CodingKeys: String, CodingKey {
        case id, date, grams, note
        case babyID = "baby_id"
        case loggedBy = "logged_by"
        case loggedByName = "logged_by_name"
        case updatedAt = "updated_at"
        case deletedAt = "deleted_at"
        case serverUpdatedAt = "server_updated_at"
    }

    init?(entry: WeightEntry, userID: UUID) {
        guard let uuid = entry.uuid, let babyID = entry.babyID else { return nil }
        id = uuid
        self.babyID = babyID
        date = entry.date
        grams = entry.grams
        note = entry.note
        loggedBy = userID
        loggedByName = entry.loggedByName
        updatedAt = entry.updatedAt
        deletedAt = entry.deletedAt
        serverUpdatedAt = nil
    }

    func apply(to entry: WeightEntry) {
        entry.uuid = id
        entry.babyID = babyID
        entry.date = date
        entry.grams = grams
        entry.note = note
        entry.loggedByName = loggedByName
        entry.updatedAt = updatedAt
        entry.deletedAt = deletedAt
        entry.needsUpload = false
    }
}

struct MemberDTO: Codable, Equatable, Identifiable {
    var babyID: UUID
    var userID: UUID
    var role: String
    var displayName: String
    var joinedAt: Date

    var id: UUID { userID }
    var isOwner: Bool { role == "owner" }

    enum CodingKeys: String, CodingKey {
        case role
        case babyID = "baby_id"
        case userID = "user_id"
        case displayName = "display_name"
        case joinedAt = "joined_at"
    }
}
