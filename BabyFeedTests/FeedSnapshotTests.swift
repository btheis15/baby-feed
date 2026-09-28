import Foundation
import Testing
@testable import BabyFeed

struct FeedSnapshotTests {
    @Test func roundTripsThroughJSON() throws {
        let snapshot = FeedSnapshot.placeholder
        let data = try JSONEncoder().encode(snapshot)
        let decoded = try JSONDecoder().decode(FeedSnapshot.self, from: data)
        #expect(decoded.lastFeed?.title == snapshot.lastFeed?.title)
        #expect(decoded.lastFeed?.detail == snapshot.lastFeed?.detail)
        #expect(decoded.last24hFeedCount == snapshot.last24hFeedCount)
        #expect(decoded.targetText == snapshot.targetText)
        let originalTime = try #require(snapshot.lastFeed?.time)
        let decodedTime = try #require(decoded.lastFeed?.time)
        #expect(abs(decodedTime.timeIntervalSince(originalTime)) < 0.01)
    }

    @Test func theDueTimeAndPinnedZoneSurviveTheTrip() throws {
        var snapshot = FeedSnapshot.placeholder
        snapshot.timeZoneIdentifier = "Europe/London"
        let decoded = try JSONDecoder().decode(FeedSnapshot.self, from: try JSONEncoder().encode(snapshot))
        let due = try #require(snapshot.nextFeedDue)
        let decodedDue = try #require(decoded.nextFeedDue)
        #expect(abs(decodedDue.timeIntervalSince(due)) < 0.01)
        #expect(decoded.timeZoneIdentifier == "Europe/London")
        #expect(decoded.timeZone.identifier == "Europe/London")
    }

    @Test func aSnapshotFromBeforeTheTimeZoneFieldStillDecodes() throws {
        // What an older build left in the App Group: no timeZoneIdentifier key.
        var legacy = FeedSnapshot.placeholder
        legacy.timeZoneIdentifier = nil
        var json = try #require(try JSONSerialization.jsonObject(with: try JSONEncoder().encode(legacy)) as? [String: Any])
        json.removeValue(forKey: "timeZoneIdentifier")
        let decoded = try JSONDecoder().decode(FeedSnapshot.self, from: try JSONSerialization.data(withJSONObject: json))
        #expect(decoded.timeZoneIdentifier == nil)
        #expect(decoded.timeZone == .current)
    }

    @Test func onlyTheWriteTimeChangingIsNotAChange() {
        let snapshot = FeedSnapshot.placeholder
        var later = snapshot
        later.updatedAt = snapshot.updatedAt.addingTimeInterval(3600)
        #expect(snapshot.sameContent(as: later), "rewriting the same numbers must not wake every widget")

        var different = later
        different.last24hFeedCount += 1
        #expect(!snapshot.sameContent(as: different))
    }

    @Test func deepLinksCarryTheKind() {
        #expect(DeepLink.log(kindRaw: nil).absoluteString == "babyfeed://log")
        #expect(DeepLink.log(kindRaw: "nursing").absoluteString == "babyfeed://log/nursing")
        #expect(DeepLink.log(kindRaw: "formula").host == "log")
        #expect(DeepLink.log(kindRaw: "formula").pathComponents.dropFirst().first == "formula")
    }
}
