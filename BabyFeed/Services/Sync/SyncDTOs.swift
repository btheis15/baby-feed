import Foundation

/// Row shapes for syncing. snake_case because that's what the server on the
/// Mac mini stores them as, so the JSON maps onto a table with no translation
/// in between and a row can be read straight out of the database.
struct BabyDTO: Codable, Equatable {
    var id: UUID
    var name: String
    var birthDate: Date?
    /// Sex and due date ride along because the WHO percentiles need both. A
    /// joining caregiver whose app didn't know them would show a different
    /// daily target for the same baby, which is worse than no sharing at all.
    var sex: String?
    var dueDate: Date?
    var createdBy: UUID?
    var updatedAt: Date
    var deletedAt: Date?
    var serverUpdatedAt: Date?

    enum CodingKeys: String, CodingKey {
        case id, name, sex
        case birthDate = "birth_date"
        case dueDate = "due_date"
        case createdBy = "created_by"
        case updatedAt = "updated_at"
        case deletedAt = "deleted_at"
        case serverUpdatedAt = "server_updated_at"
    }

    init(id: UUID, name: String, birthDate: Date?, sex: String?, dueDate: Date?,
         createdBy: UUID?, updatedAt: Date, deletedAt: Date?, serverUpdatedAt: Date?) {
        self.id = id
        self.name = name
        self.birthDate = birthDate
        self.sex = sex
        self.dueDate = dueDate
        self.createdBy = createdBy
        self.updatedAt = updatedAt
        self.deletedAt = deletedAt
        self.serverUpdatedAt = serverUpdatedAt
    }

    init(baby: Baby, createdBy: UUID?) {
        id = baby.uuid
        name = baby.name
        birthDate = baby.birthDate
        sex = baby.sexRaw
        dueDate = baby.dueDate
        self.createdBy = createdBy
        updatedAt = baby.updatedAt
        deletedAt = baby.deletedAt
        serverUpdatedAt = nil
    }

    func apply(to baby: Baby) {
        baby.name = name
        baby.birthDate = birthDate
        if let sex { baby.sexRaw = sex }
        baby.dueDate = dueDate
        baby.updatedAt = updatedAt
        baby.deletedAt = deletedAt
        if let createdBy { baby.ownerUserID = createdBy.uuidString }
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

struct CareNoteDTO: Codable, Equatable {
    var id: UUID
    var babyID: UUID
    var date: Date
    var kind: String
    var note: String
    var severity: Int?
    var resolvedAt: Date?
    var loggedBy: UUID?
    var loggedByName: String
    var updatedAt: Date
    var deletedAt: Date?
    var serverUpdatedAt: Date?

    enum CodingKeys: String, CodingKey {
        case id, date, kind, note, severity
        case babyID = "baby_id"
        case resolvedAt = "resolved_at"
        case loggedBy = "logged_by"
        case loggedByName = "logged_by_name"
        case updatedAt = "updated_at"
        case deletedAt = "deleted_at"
        case serverUpdatedAt = "server_updated_at"
    }

    init?(entry: CareNote, userID: UUID?) {
        guard let uuid = entry.uuid, let babyID = entry.babyID else { return nil }
        id = uuid
        self.babyID = babyID
        date = entry.date
        kind = entry.kindRaw
        note = entry.note
        severity = entry.severityRaw
        resolvedAt = entry.resolvedAt
        loggedBy = userID
        loggedByName = entry.loggedByName
        updatedAt = entry.updatedAt
        deletedAt = entry.deletedAt
        serverUpdatedAt = nil
    }

    func apply(to entry: CareNote) {
        entry.uuid = id
        entry.babyID = babyID
        entry.date = date
        entry.kindRaw = kind
        entry.note = note
        entry.severityRaw = severity
        entry.resolvedAt = resolvedAt
        entry.loggedByName = loggedByName
        entry.updatedAt = updatedAt
        entry.deletedAt = deletedAt
        entry.needsUpload = false
    }
}

struct DiaperDTO: Codable, Equatable {
    var id: UUID
    var babyID: UUID
    var time: Date
    var kind: String
    var note: String
    var loggedBy: UUID?
    var loggedByName: String
    var updatedAt: Date
    var deletedAt: Date?
    var serverUpdatedAt: Date?

    enum CodingKeys: String, CodingKey {
        case id, time, kind, note
        case babyID = "baby_id"
        case loggedBy = "logged_by"
        case loggedByName = "logged_by_name"
        case updatedAt = "updated_at"
        case deletedAt = "deleted_at"
        case serverUpdatedAt = "server_updated_at"
    }

    init?(entry: DiaperEntry, userID: UUID?) {
        guard let uuid = entry.uuid, let babyID = entry.babyID else { return nil }
        id = uuid
        self.babyID = babyID
        time = entry.time
        kind = entry.kindRaw
        note = entry.note
        loggedBy = userID
        loggedByName = entry.loggedByName
        updatedAt = entry.updatedAt
        deletedAt = entry.deletedAt
        serverUpdatedAt = nil
    }

    func apply(to entry: DiaperEntry) {
        entry.uuid = id
        entry.babyID = babyID
        entry.time = time
        entry.kindRaw = kind
        entry.note = note
        entry.loggedByName = loggedByName
        entry.updatedAt = updatedAt
        entry.deletedAt = deletedAt
        entry.needsUpload = false
    }
}

struct SolidFoodDTO: Codable, Equatable {
    var id: UUID
    var babyID: UUID
    var time: Date
    var name: String
    var texture: String
    var reaction: String
    var note: String
    var loggedBy: UUID?
    var loggedByName: String
    var updatedAt: Date
    var deletedAt: Date?
    var serverUpdatedAt: Date?

    enum CodingKeys: String, CodingKey {
        case id, time, name, texture, reaction, note
        case babyID = "baby_id"
        case loggedBy = "logged_by"
        case loggedByName = "logged_by_name"
        case updatedAt = "updated_at"
        case deletedAt = "deleted_at"
        case serverUpdatedAt = "server_updated_at"
    }

    init?(entry: SolidFoodEntry, userID: UUID?) {
        guard let uuid = entry.uuid, let babyID = entry.babyID else { return nil }
        id = uuid
        self.babyID = babyID
        time = entry.time
        name = entry.name
        texture = entry.textureRaw
        reaction = entry.reactionRaw
        note = entry.note
        loggedBy = userID
        loggedByName = entry.loggedByName
        updatedAt = entry.updatedAt
        deletedAt = entry.deletedAt
        serverUpdatedAt = nil
    }

    func apply(to entry: SolidFoodEntry) {
        entry.uuid = id
        entry.babyID = babyID
        entry.time = time
        entry.name = name
        entry.textureRaw = texture
        entry.reactionRaw = reaction
        entry.note = note
        entry.loggedByName = loggedByName
        entry.updatedAt = updatedAt
        entry.deletedAt = deletedAt
        entry.needsUpload = false
    }
}

/// A baby as /v1/me lists it: the baby's own fields plus this caregiver's role.
struct MembershipDTO: Codable, Equatable, Identifiable {
    var id: UUID
    var name: String
    var role: String
    var birthDate: Date?
    var sex: String?
    var dueDate: Date?
    var createdBy: UUID?
    var updatedAt: Date
    var deletedAt: Date?
    var serverUpdatedAt: Date?

    var isOwner: Bool { role == "owner" }

    enum CodingKeys: String, CodingKey {
        case id, name, role, sex
        case birthDate = "birth_date"
        case dueDate = "due_date"
        case createdBy = "created_by"
        case updatedAt = "updated_at"
        case deletedAt = "deleted_at"
        case serverUpdatedAt = "server_updated_at"
    }

    var baby: BabyDTO {
        BabyDTO(id: id, name: name, birthDate: birthDate, sex: sex, dueDate: dueDate,
                createdBy: createdBy, updatedAt: updatedAt, deletedAt: deletedAt,
                serverUpdatedAt: serverUpdatedAt)
    }
}
