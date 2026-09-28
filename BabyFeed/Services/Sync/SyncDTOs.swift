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
    /// The concern this note updates. A late column: always sent by this app
    /// (null included, so an unlink reaches the other phone), and read back
    /// only when the server sent it, so a server or phone from before
    /// concerns can't unlink a note by not knowing the field.
    var concernID: UUID?
    var concernIDWasSent = true
    var loggedBy: UUID?
    var loggedByName: String
    var updatedAt: Date
    var deletedAt: Date?
    var serverUpdatedAt: Date?

    enum CodingKeys: String, CodingKey {
        case id, date, kind, note, severity
        case babyID = "baby_id"
        case resolvedAt = "resolved_at"
        case concernID = "concern_id"
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
        concernID = entry.concernID
        loggedBy = userID
        loggedByName = entry.loggedByName
        updatedAt = entry.updatedAt
        deletedAt = entry.deletedAt
        serverUpdatedAt = nil
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        babyID = try container.decode(UUID.self, forKey: .babyID)
        date = try container.decode(Date.self, forKey: .date)
        kind = try container.decode(String.self, forKey: .kind)
        note = try container.decodeIfPresent(String.self, forKey: .note) ?? ""
        severity = try container.decodeIfPresent(Int.self, forKey: .severity)
        resolvedAt = try container.decodeIfPresent(Date.self, forKey: .resolvedAt)
        concernIDWasSent = container.contains(.concernID)
        concernID = try container.decodeIfPresent(UUID.self, forKey: .concernID)
        loggedBy = try container.decodeIfPresent(UUID.self, forKey: .loggedBy)
        loggedByName = try container.decodeIfPresent(String.self, forKey: .loggedByName) ?? ""
        updatedAt = try container.decode(Date.self, forKey: .updatedAt)
        deletedAt = try container.decodeIfPresent(Date.self, forKey: .deletedAt)
        serverUpdatedAt = try container.decodeIfPresent(Date.self, forKey: .serverUpdatedAt)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(babyID, forKey: .babyID)
        try container.encode(date, forKey: .date)
        try container.encode(kind, forKey: .kind)
        try container.encode(note, forKey: .note)
        try container.encodeIfPresent(severity, forKey: .severity)
        try container.encodeIfPresent(resolvedAt, forKey: .resolvedAt)
        // Always present, null included: this app knows the field.
        try container.encode(concernID, forKey: .concernID)
        try container.encodeIfPresent(loggedBy, forKey: .loggedBy)
        try container.encode(loggedByName, forKey: .loggedByName)
        try container.encode(updatedAt, forKey: .updatedAt)
        try container.encodeIfPresent(deletedAt, forKey: .deletedAt)
        try container.encodeIfPresent(serverUpdatedAt, forKey: .serverUpdatedAt)
    }

    func apply(to entry: CareNote) {
        entry.uuid = id
        entry.babyID = babyID
        entry.date = date
        entry.kindRaw = kind
        entry.note = note
        entry.severityRaw = severity
        entry.resolvedAt = resolvedAt
        if concernIDWasSent { entry.concernID = concernID }
        entry.loggedByName = loggedByName
        entry.updatedAt = updatedAt
        entry.deletedAt = deletedAt
        entry.needsUpload = false
    }
}

struct HealthConcernDTO: Codable, Equatable {
    var id: UUID
    var babyID: UUID
    var title: String
    var kind: String
    var startedAt: Date
    var resolvedAt: Date?
    var severity: Int?
    var note: String
    var outcome: String
    var loggedBy: UUID?
    var loggedByName: String
    var updatedAt: Date
    var deletedAt: Date?
    var serverUpdatedAt: Date?

    enum CodingKeys: String, CodingKey {
        case id, title, kind, severity, note, outcome
        case babyID = "baby_id"
        case startedAt = "started_at"
        case resolvedAt = "resolved_at"
        case loggedBy = "logged_by"
        case loggedByName = "logged_by_name"
        case updatedAt = "updated_at"
        case deletedAt = "deleted_at"
        case serverUpdatedAt = "server_updated_at"
    }

    init?(entry: HealthConcern, userID: UUID?) {
        guard let uuid = entry.uuid, let babyID = entry.babyID else { return nil }
        id = uuid
        self.babyID = babyID
        title = entry.title
        kind = entry.kindRaw
        startedAt = entry.startedAt
        resolvedAt = entry.resolvedAt
        severity = entry.severityRaw
        note = entry.note
        outcome = entry.outcome
        loggedBy = userID
        loggedByName = entry.loggedByName
        updatedAt = entry.updatedAt
        deletedAt = entry.deletedAt
        serverUpdatedAt = nil
    }

    func apply(to entry: HealthConcern) {
        entry.uuid = id
        entry.babyID = babyID
        entry.title = title
        entry.kindRaw = kind
        entry.startedAt = startedAt
        entry.resolvedAt = resolvedAt
        entry.severityRaw = severity
        entry.note = note
        entry.outcome = outcome
        entry.loggedByName = loggedByName
        entry.updatedAt = updatedAt
        entry.deletedAt = deletedAt
        entry.needsUpload = false
    }
}

struct MedicationDTO: Codable, Equatable {
    var id: UUID
    var babyID: UUID
    var name: String
    var kind: String
    var doseAmount: Double?
    var doseUnit: String
    var schedule: String
    var timesPerDay: Int?
    var intervalHours: Double?
    var minHoursBetween: Double?
    var maxDosesPer24h: Int?
    var startDate: Date
    var endDate: Date?
    var instructions: String
    var loggedBy: UUID?
    var loggedByName: String
    var updatedAt: Date
    var deletedAt: Date?
    var serverUpdatedAt: Date?

    enum CodingKeys: String, CodingKey {
        case id, name, kind, schedule, instructions
        case babyID = "baby_id"
        case doseAmount = "dose_amount"
        case doseUnit = "dose_unit"
        case timesPerDay = "times_per_day"
        case intervalHours = "interval_hours"
        case minHoursBetween = "min_hours_between"
        case maxDosesPer24h = "max_doses_per_24h"
        case startDate = "start_date"
        case endDate = "end_date"
        case loggedBy = "logged_by"
        case loggedByName = "logged_by_name"
        case updatedAt = "updated_at"
        case deletedAt = "deleted_at"
        case serverUpdatedAt = "server_updated_at"
    }

    init?(entry: Medication, userID: UUID?) {
        guard let uuid = entry.uuid, let babyID = entry.babyID else { return nil }
        id = uuid
        self.babyID = babyID
        name = entry.name
        kind = entry.kindRaw
        doseAmount = entry.doseAmount
        doseUnit = entry.doseUnitRaw
        schedule = entry.scheduleRaw
        timesPerDay = entry.timesPerDay
        intervalHours = entry.intervalHours
        minHoursBetween = entry.minHoursBetween
        maxDosesPer24h = entry.maxDosesPer24h
        startDate = entry.startDate
        endDate = entry.endDate
        instructions = entry.instructions
        loggedBy = userID
        loggedByName = entry.loggedByName
        updatedAt = entry.updatedAt
        deletedAt = entry.deletedAt
        serverUpdatedAt = nil
    }

    func apply(to entry: Medication) {
        entry.uuid = id
        entry.babyID = babyID
        entry.name = name
        entry.kindRaw = kind
        entry.doseAmount = doseAmount
        entry.doseUnitRaw = doseUnit
        entry.scheduleRaw = schedule
        entry.timesPerDay = timesPerDay
        entry.intervalHours = intervalHours
        entry.minHoursBetween = minHoursBetween
        entry.maxDosesPer24h = maxDosesPer24h
        entry.startDate = startDate
        entry.endDate = endDate
        entry.instructions = instructions
        entry.loggedByName = loggedByName
        entry.updatedAt = updatedAt
        entry.deletedAt = deletedAt
        entry.needsUpload = false
    }
}

struct MedicationDoseDTO: Codable, Equatable {
    var id: UUID
    var babyID: UUID
    var medicationID: UUID?
    var medicationName: String
    var time: Date
    var amount: Double?
    var unit: String?
    var note: String
    var loggedBy: UUID?
    var loggedByName: String
    var updatedAt: Date
    var deletedAt: Date?
    var serverUpdatedAt: Date?

    enum CodingKeys: String, CodingKey {
        case id, time, amount, unit, note
        case babyID = "baby_id"
        case medicationID = "medication_id"
        case medicationName = "medication_name"
        case loggedBy = "logged_by"
        case loggedByName = "logged_by_name"
        case updatedAt = "updated_at"
        case deletedAt = "deleted_at"
        case serverUpdatedAt = "server_updated_at"
    }

    init?(entry: MedicationDose, userID: UUID?) {
        guard let uuid = entry.uuid, let babyID = entry.babyID else { return nil }
        id = uuid
        self.babyID = babyID
        medicationID = entry.medicationID
        medicationName = entry.medicationName
        time = entry.time
        amount = entry.amount
        unit = entry.unitRaw
        note = entry.note
        loggedBy = userID
        loggedByName = entry.loggedByName
        updatedAt = entry.updatedAt
        deletedAt = entry.deletedAt
        serverUpdatedAt = nil
    }

    func apply(to entry: MedicationDose) {
        entry.uuid = id
        entry.babyID = babyID
        entry.medicationID = medicationID
        entry.medicationName = medicationName
        entry.time = time
        entry.amount = amount
        entry.unitRaw = unit
        entry.note = note
        entry.loggedByName = loggedByName
        entry.updatedAt = updatedAt
        entry.deletedAt = deletedAt
        entry.needsUpload = false
    }
}

struct DoctorVisitDTO: Codable, Equatable {
    var id: UUID
    var babyID: UUID
    var date: Date
    var kind: String
    var provider: String
    var reason: String
    var doctorNotes: String
    var followUpDate: Date?
    var followUpNote: String
    var vaccines: String
    var weightEntryID: UUID?
    var loggedBy: UUID?
    var loggedByName: String
    var updatedAt: Date
    var deletedAt: Date?
    var serverUpdatedAt: Date?

    enum CodingKeys: String, CodingKey {
        case id, date, kind, provider, reason, vaccines
        case babyID = "baby_id"
        case doctorNotes = "doctor_notes"
        case followUpDate = "follow_up_date"
        case followUpNote = "follow_up_note"
        case weightEntryID = "weight_entry_id"
        case loggedBy = "logged_by"
        case loggedByName = "logged_by_name"
        case updatedAt = "updated_at"
        case deletedAt = "deleted_at"
        case serverUpdatedAt = "server_updated_at"
    }

    init?(entry: DoctorVisit, userID: UUID?) {
        guard let uuid = entry.uuid, let babyID = entry.babyID else { return nil }
        id = uuid
        self.babyID = babyID
        date = entry.date
        kind = entry.kindRaw
        provider = entry.provider
        reason = entry.reason
        doctorNotes = entry.doctorNotes
        followUpDate = entry.followUpDate
        followUpNote = entry.followUpNote
        vaccines = entry.vaccines
        weightEntryID = entry.weightEntryID
        loggedBy = userID
        loggedByName = entry.loggedByName
        updatedAt = entry.updatedAt
        deletedAt = entry.deletedAt
        serverUpdatedAt = nil
    }

    func apply(to entry: DoctorVisit) {
        entry.uuid = id
        entry.babyID = babyID
        entry.date = date
        entry.kindRaw = kind
        entry.provider = provider
        entry.reason = reason
        entry.doctorNotes = doctorNotes
        entry.followUpDate = followUpDate
        entry.followUpNote = followUpNote
        entry.vaccines = vaccines
        entry.weightEntryID = weightEntryID
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
