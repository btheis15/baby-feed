import CryptoKit
import Foundation

/// Where a sealed baby's rows cross into and out of `SealedLog`, so the rest
/// of `SyncEngine` deals in the same DTOs and the same merge for every baby.
///
/// Going up, each row becomes the DTO a readable log would send, sealed whole.
/// Coming down, each box is opened and its row put back in the page beside
/// the readable ones, then merged by `SyncMerge` exactly as before.
@MainActor
enum SealedSync {
    // MARK: Up

    /// A row of any kind, sealed for its baby. Nil for a row with no id or baby.
    static func seal(_ row: any SyncableRow & CareEntry, userID: UUID?, key: SymmetricKey) throws -> SealedLog.Row? {
        guard let id = row.uuid, let babyID = row.babyID else { return nil }
        let table = SyncEngine.table(of: row)
        func box<DTO: Codable>(_ dto: DTO?) throws -> SealedLog.Row? {
            guard let dto else { return nil }
            return try SealedLog.sealRow(dto, table: table, id: id, babyID: babyID, updatedAt: row.updatedAt, key: key)
        }
        // The DTOs that take a non-optional user id get a stand-in, as the
        // readable push does; the server records the real one.
        switch row {
        case let entry as FeedEntry: return try box(FeedDTO(entry: entry, userID: userID ?? UUID()))
        case let entry as WeightEntry: return try box(WeightDTO(entry: entry, userID: userID ?? UUID()))
        case let entry as CareNote: return try box(CareNoteDTO(entry: entry, userID: userID))
        case let entry as DiaperEntry: return try box(DiaperDTO(entry: entry, userID: userID))
        case let entry as SolidFoodEntry: return try box(SolidFoodDTO(entry: entry, userID: userID))
        case let entry as HealthConcern: return try box(HealthConcernDTO(entry: entry, userID: userID))
        case let entry as Medication: return try box(MedicationDTO(entry: entry, userID: userID))
        case let entry as MedicationDose: return try box(MedicationDoseDTO(entry: entry, userID: userID))
        case let entry as DoctorVisit: return try box(DoctorVisitDTO(entry: entry, userID: userID))
        default: return nil
        }
    }

    /// A sealed baby goes up twice: a blank readable row, which is what makes
    /// the server create the log and its owner, and its real details sealed.
    static func seal(_ baby: Baby, userID: UUID?, key: SymmetricKey) throws -> (blank: BabyDTO, sealed: SealedLog.Row) {
        let dto = BabyDTO(baby: baby, createdBy: userID)
        let blank = BabyDTO(id: baby.uuid, name: "", birthDate: nil, sex: nil, dueDate: nil, createdBy: userID,
                            updatedAt: baby.updatedAt, deletedAt: baby.deletedAt, serverUpdatedAt: nil, sealed: true)
        let sealed = try SealedLog.sealRow(dto, table: "babies", id: baby.uuid, babyID: baby.uuid,
                                           updatedAt: baby.updatedAt, key: key)
        return (blank, sealed)
    }

    // MARK: Down

    /// A page for a sealed baby, with its boxes opened into the readable lists.
    /// The blank readable baby row is dropped: it would blank the name here.
    /// Boxes that won't open are counted, not trusted.
    static func open(_ page: SyncClient.PullResult, babyID: UUID, key: SymmetricKey)
        -> (page: SyncClient.PullResult, unreadable: Int) {
        var page = page
        page.babies = []
        var unreadable = 0
        for row in page.sealed {
            // A box claiming another baby is refused before it's opened: the
            // context it was sealed with names its own.
            guard row.babyID == babyID else {
                unreadable += 1
                continue
            }
            do {
                let (table, json) = try SealedLog.openRow(row, key: key)
                try add(json, table: table, id: row.id, to: &page)
            } catch {
                unreadable += 1
            }
        }
        page.members = openNames(page.members, babyID: babyID, key: key)
        return (page, unreadable)
    }

    /// Decodes an opened row as its table, and checks it is the row the box
    /// was for: the id inside has to match the id it was sealed under.
    private static func add(_ json: Data, table: String, id: UUID, to page: inout SyncClient.PullResult) throws {
        func row<DTO: Decodable & SyncRow>(_ type: DTO.Type) throws -> DTO {
            let dto = try SealedLog.decode(type, from: json)
            guard dto.id == id else { throw SealedLog.Failure.cannotOpen }
            return dto
        }
        switch table {
        case "babies":
            let dto = try SealedLog.decode(BabyDTO.self, from: json)
            guard dto.id == id else { throw SealedLog.Failure.cannotOpen }
            page.babies.append(dto)
        case "feeds": page.feeds.append(try row(FeedDTO.self))
        case "weights": page.weights.append(try row(WeightDTO.self))
        case "care_notes": page.careNotes.append(try row(CareNoteDTO.self))
        case "diapers": page.diapers.append(try row(DiaperDTO.self))
        case "solid_foods": page.solidFoods.append(try row(SolidFoodDTO.self))
        case "concerns": page.concerns.append(try row(HealthConcernDTO.self))
        case "medications": page.medications.append(try row(MedicationDTO.self))
        case "medication_doses": page.medicationDoses.append(try row(MedicationDoseDTO.self))
        case "doctor_visits": page.doctorVisits.append(try row(DoctorVisitDTO.self))
        default: throw SealedLog.Failure.unknownTable(table)
        }
    }

    /// Caregiver names on a sealed log, opened. One that hasn't been set yet
    /// (or won't open) stays blank, which the screens show as "a caregiver".
    static func openNames(_ members: [MemberDTO], babyID: UUID, key: SymmetricKey) -> [MemberDTO] {
        members.map { member in
            var member = member
            if let sealed = member.sealedName {
                member.displayName = SealedLog.openName(sealed, babyID: babyID, userID: member.userID, key: key) ?? ""
            }
            return member
        }
    }
}
