import Foundation
import Testing
@testable import BabyFeed

/// A server once sent `sealed` on pulled babies as SQLite's 1 or 0. That
/// failed the whole page, so a newly joined phone never got its first pull
/// through. The app reads either form now, so a server already deployed can't
/// break a phone that way again.
struct SealedPullDecodingTests {
    private let babyID = UUID()

    /// A pull page shaped like the server's, with `babies[0].sealed` as given.
    private func page(sealed: String) -> Data {
        Data("""
        {"baby_id":"\(babyID.uuidString)",
         "babies":[{"id":"\(babyID.uuidString)","name":"","birth_date":null,"sex":null,"due_date":null,
                    "created_by":null,"updated_at":"2026-10-08T10:00:00.000Z","deleted_at":null,
                    "server_updated_at":"2026-10-08T10:00:01.000Z","sealed":\(sealed)}],
         "feeds":[],"weights":[],"care_notes":[],"diapers":[],"solid_foods":[],"concerns":[],
         "medications":[],"medication_doses":[],"doctor_visits":[],"sealed":[],"members":[],
         "has_more":false,"next_since":"2026-10-08T10:00:01.000Z","server_time":"2026-10-08T10:00:02.000Z"}
        """.utf8)
    }

    @Test func aPulledBabyWithSealedAsOneIsSealed() throws {
        let result = try SyncClient.decoder.decode(SyncClient.PullResult.self, from: page(sealed: "1"))
        #expect(result.babies.count == 1)
        #expect(result.babies[0].sealed == true)
    }

    @Test func aPulledBabyWithSealedAsZeroIsNotSealed() throws {
        let result = try SyncClient.decoder.decode(SyncClient.PullResult.self, from: page(sealed: "0"))
        #expect(result.babies.count == 1)
        #expect(result.babies[0].sealed == false)
    }

    @Test func booleansAndAMissingKeyStillDecode() throws {
        #expect(try SyncClient.decoder.decode(SyncClient.PullResult.self, from: page(sealed: "true")).babies[0].sealed == true)
        #expect(try SyncClient.decoder.decode(SyncClient.PullResult.self, from: page(sealed: "false")).babies[0].sealed == false)
        #expect(try SyncClient.decoder.decode(SyncClient.PullResult.self, from: page(sealed: "null")).babies[0].sealed == nil)
    }

    @Test func aMembershipReadsSealedAsANumberToo() throws {
        func membership(_ sealed: String) throws -> MembershipDTO {
            let json = """
            {"id":"\(babyID.uuidString)","name":"","role":"caregiver","updated_at":"2026-10-08T10:00:00.000Z",
             "sealed":\(sealed),"wrapped_key":null,"sealed_name":null}
            """
            return try SyncClient.decoder.decode(MembershipDTO.self, from: Data(json.utf8))
        }
        #expect(try membership("1").isSealed)
        #expect(try membership("0").sealed == false)
        #expect(try membership("true").baby.sealed == true)
    }

    @Test func aBabyRoundTripsThroughTheEncoder() throws {
        let dto = BabyDTO(id: babyID, name: "Maple", birthDate: nil, sex: "female", dueDate: nil,
                          createdBy: nil, updatedAt: Date(timeIntervalSince1970: 1_800_000_000),
                          deletedAt: nil, serverUpdatedAt: nil, sealed: true)
        let decoded = try SyncClient.decoder.decode(BabyDTO.self, from: SyncClient.encoder.encode(dto))
        #expect(decoded == dto)
    }
}
