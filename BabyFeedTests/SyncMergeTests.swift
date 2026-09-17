import Foundation
import Testing
@testable import BabyFeed

struct SyncMergeTests {
    private let base = Date(timeIntervalSince1970: 1_700_000_000)

    @Test func newerRemoteWins() {
        #expect(SyncMerge.remoteWins(remoteUpdatedAt: base.addingTimeInterval(10), localUpdatedAt: base, localNeedsUpload: false))
        #expect(SyncMerge.remoteWins(remoteUpdatedAt: base.addingTimeInterval(10), localUpdatedAt: base, localNeedsUpload: true))
    }

    @Test func olderRemoteLoses() {
        #expect(!SyncMerge.remoteWins(remoteUpdatedAt: base, localUpdatedAt: base.addingTimeInterval(10), localNeedsUpload: false))
        #expect(!SyncMerge.remoteWins(remoteUpdatedAt: base, localUpdatedAt: base.addingTimeInterval(10), localNeedsUpload: true))
    }

    @Test func tieKeepsUnpushedLocalEdit() {
        // Same timestamp: a pushed local row is refreshed from the server,
        // but an un-pushed local edit is kept so it isn't silently lost.
        #expect(SyncMerge.remoteWins(remoteUpdatedAt: base, localUpdatedAt: base, localNeedsUpload: false))
        #expect(!SyncMerge.remoteWins(remoteUpdatedAt: base, localUpdatedAt: base, localNeedsUpload: true))
    }

    @Test func inviteCodesAreNormalized() {
        #expect(SyncMerge.normalizedInviteCode(" abc-123 ") == "ABC123")
        #expect(SyncMerge.normalizedInviteCode("AB C1 23") == "ABC123")
        #expect(SyncMerge.isPlausibleInviteCode("abc123"))
        #expect(!SyncMerge.isPlausibleInviteCode("abc12"))
        #expect(!SyncMerge.isPlausibleInviteCode(""))
    }

    @Test func inviteMessageCarriesCodeAndLink() {
        let message = SyncMerge.inviteMessage(babyName: "Nora", code: "ABC123")
        #expect(message.contains("Nora"))
        #expect(message.contains("ABC123"))
        #expect(message.contains("babyfeed://join/ABC123"))
    }

    @Test func watermarkAdvancesWithOverlap() {
        let seen = [base, base.addingTimeInterval(100), base.addingTimeInterval(50)]
        let next = SyncMerge.nextWatermark(previous: nil, seen: seen)
        #expect(next == base.addingTimeInterval(99))
    }

    @Test func watermarkNeverMovesBackwards() {
        let previous = base.addingTimeInterval(500)
        #expect(SyncMerge.nextWatermark(previous: previous, seen: [base]) == previous)
        #expect(SyncMerge.nextWatermark(previous: previous, seen: []) == previous)
        #expect(SyncMerge.nextWatermark(previous: nil, seen: []) == nil)
    }

    @Test func displayNameFallsBackSensibly() {
        #expect(SyncMerge.suggestedDisplayName(givenName: "Brian", familyName: "T", email: "b@x.com") == "Brian")
        #expect(SyncMerge.suggestedDisplayName(givenName: " ", familyName: "Theis", email: nil) == "Theis")
        #expect(SyncMerge.suggestedDisplayName(givenName: nil, familyName: nil, email: "brian@example.com") == "brian")
        #expect(SyncMerge.suggestedDisplayName(givenName: nil, familyName: nil, email: nil) == "")
    }
}

struct SyncDTOTests {
    @Test func feedRoundTripsThroughDTO() throws {
        let userID = UUID()
        let babyID = UUID()
        let entry = FeedEntry(babyID: babyID, kind: .breastMilk, amountML: 90, note: "sleepy", loggedByName: "Brian")
        let dto = try #require(FeedDTO(entry: entry, userID: userID))
        #expect(dto.babyID == babyID)
        #expect(dto.kind == "breastMilk")
        #expect(dto.amountML == 90)
        #expect(dto.loggedBy == userID)

        let copy = FeedEntry(kind: .formula)
        dto.apply(to: copy)
        #expect(copy.uuid == entry.uuid)
        #expect(copy.kind == .breastMilk)
        #expect(copy.amountML == 90)
        #expect(copy.note == "sleepy")
        #expect(copy.loggedByName == "Brian")
        #expect(copy.needsUpload == false)
    }

    @Test func feedDTORequiresBabyAndUUID() {
        let orphan = FeedEntry(kind: .formula, amountML: 60)
        #expect(orphan.babyID == nil)
        #expect(FeedDTO(entry: orphan, userID: UUID()) == nil)
    }

    @Test func dtoKeysAreSnakeCase() throws {
        let entry = FeedEntry(babyID: UUID(), kind: .nursing, durationMinutes: 12, side: .left)
        let dto = try #require(FeedDTO(entry: entry, userID: UUID()))
        let json = try JSONEncoder().encode(dto)
        let object = try #require(JSONSerialization.jsonObject(with: json) as? [String: Any])
        #expect(object["baby_id"] != nil)
        #expect(object["duration_minutes"] as? Int == 12)
        #expect(object["logged_by_name"] as? String == "")
        #expect(object["deleted_at"] == nil || object["deleted_at"] is NSNull)
    }

    @Test func softDeleteQueuesForUpload() {
        let entry = FeedEntry(babyID: UUID(), kind: .formula, amountML: 60)
        entry.needsUpload = false
        entry.softDelete()
        #expect(entry.deletedAt != nil)
        #expect(entry.needsUpload)
        #expect([entry].active(for: nil).isEmpty)
    }

    @Test func activeFilterRespectsBaby() {
        let a = UUID(), b = UUID()
        let entries = [
            FeedEntry(babyID: a, kind: .formula, amountML: 60),
            FeedEntry(babyID: b, kind: .formula, amountML: 60),
            FeedEntry(babyID: a, kind: .nursing, durationMinutes: 5),
        ]
        entries[2].softDelete()
        #expect(entries.active(for: a).count == 1)
        #expect(entries.active(for: b).count == 1)
        #expect(entries.active(for: nil).count == 2)
    }
}
