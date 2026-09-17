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

    @Test func deepLinksCarryTheKind() {
        #expect(DeepLink.log(kindRaw: nil).absoluteString == "babyfeed://log")
        #expect(DeepLink.log(kindRaw: "nursing").absoluteString == "babyfeed://log/nursing")
        #expect(DeepLink.log(kindRaw: "formula").host == "log")
        #expect(DeepLink.log(kindRaw: "formula").pathComponents.dropFirst().first == "formula")
    }
}
