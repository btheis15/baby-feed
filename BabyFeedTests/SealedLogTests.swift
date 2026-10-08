import CryptoKit
import Foundation
import SwiftData
import Testing
@testable import BabyFeed

/// End-to-end encryption for babies added from now on. Nothing here talks to
/// a server: it's the boxes, the keys and the link, and that a page pulled
/// for a sealed log comes out as the same DTOs a readable one does.
@MainActor
struct SealedLogTests {
    private let babyID = UUID()
    private let key = BabyKey.generate()
    private let phrase = RecoveryKey.generate()

    private func feedDTO(id: UUID = UUID(), note: String = "spit up a little") -> FeedDTO {
        let entry = FeedEntry(uuid: id, babyID: babyID, startTime: .now, kind: .formula, amountML: 90, note: note,
                              loggedByName: "Annette")
        return FeedDTO(entry: entry, userID: UUID())!
    }

    // MARK: Boxes

    @Test func aRowOpensWithItsKeyAndNothingReadableTravels() throws {
        let dto = feedDTO()
        let row = try SealedLog.sealRow(dto, table: "feeds", id: dto.id, babyID: babyID, updatedAt: dto.updatedAt, key: key)
        #expect(!row.sealed.contains("Annette"))
        #expect(Data(base64Encoded: row.sealed).map { String(decoding: $0, as: UTF8.self).contains("spit up") } == false)

        let (table, json) = try SealedLog.openRow(row, key: key)
        #expect(table == "feeds")
        let opened = try SealedLog.decode(FeedDTO.self, from: json)
        #expect(opened.id == dto.id)
        #expect(opened.note == "spit up a little")
        #expect(opened.loggedByName == "Annette")
        #expect(opened.amountML == 90)
    }

    @Test func aBoxWontOpenWithAnotherKeyOrOnAnotherRow() throws {
        let dto = feedDTO()
        let row = try SealedLog.sealRow(dto, table: "feeds", id: dto.id, babyID: babyID, updatedAt: dto.updatedAt, key: key)
        #expect(throws: SealedLog.Failure.cannotOpen) { try SealedLog.openRow(row, key: BabyKey.generate()) }

        // The server moving a box onto another row, or another baby.
        let moved = SealedLog.Row(id: UUID(), babyID: babyID, updatedAt: row.updatedAt, sealed: row.sealed)
        #expect(throws: SealedLog.Failure.cannotOpen) { try SealedLog.openRow(moved, key: key) }
        let otherBaby = SealedLog.Row(id: row.id, babyID: UUID(), updatedAt: row.updatedAt, sealed: row.sealed)
        #expect(throws: SealedLog.Failure.cannotOpen) { try SealedLog.openRow(otherBaby, key: key) }
    }

    // MARK: Pages

    @Test func aPulledPageOpensIntoTheSameListsAReadableOneHas() throws {
        let feed = feedDTO()
        let feedBox = try SealedLog.sealRow(feed, table: "feeds", id: feed.id, babyID: babyID,
                                            updatedAt: feed.updatedAt, key: key)
        let baby = Baby(uuid: babyID, name: "Nora", birthDate: .now, isSealed: true)
        let (blank, babyBox) = try SealedSync.seal(baby, userID: UUID(), key: key)
        #expect(blank.name.isEmpty && blank.birthDate == nil && blank.sealed == true)

        let garbage = SealedLog.Row(id: UUID(), babyID: babyID, updatedAt: .now, sealed: Data(repeating: 7, count: 64).base64EncodedString())
        let page = SyncClient.PullResult(babies: [blank], sealed: [babyBox, feedBox, garbage])
        let (opened, unreadable) = SealedSync.open(page, babyID: babyID, key: key)

        #expect(opened.babies.map(\.name) == ["Nora"], "the blank readable row is dropped, the sealed one used")
        #expect(opened.feeds.map(\.id) == [feed.id])
        #expect(unreadable == 1)
    }

    @Test func aBoxForAnotherBabyIsNeverOpenedIntoThisOne() throws {
        let other = UUID()
        let feed = feedDTO()
        let box = try SealedLog.sealRow(feed, table: "feeds", id: feed.id, babyID: other, updatedAt: .now, key: key)
        let (opened, unreadable) = SealedSync.open(SyncClient.PullResult(sealed: [box]), babyID: babyID, key: key)
        #expect(opened.feeds.isEmpty)
        #expect(unreadable == 1)
    }

    @Test func everyKindOfRowSealsAndComesBack() throws {
        let entries: [any SyncableRow & CareEntry] = [
            DiaperEntry(babyID: babyID, kind: .both),
            WeightEntry(babyID: babyID, grams: 3400),
            CareNote(babyID: babyID, kind: .allFine, note: FineDays.noteText),
            MedicationDose(babyID: babyID, medicationName: "Vitamin D"),
        ]
        let boxes = try entries.compactMap { try SealedSync.seal($0, userID: UUID(), key: key) }
        #expect(boxes.count == entries.count)
        let (opened, unreadable) = SealedSync.open(SyncClient.PullResult(sealed: boxes), babyID: babyID, key: key)
        #expect(unreadable == 0)
        #expect(opened.diapers.first?.kind == "both")
        #expect(opened.weights.first?.grams == 3400)
        #expect(opened.careNotes.first?.kind == "allFine")
        #expect(opened.medicationDoses.first?.medicationName == "Vitamin D")
    }

    // MARK: Names

    @Test func aNameOpensOnlyForTheCaregiverAndLogItWasSealedFor() throws {
        let userID = UUID()
        let sealed = try SealedLog.sealName("Annette", babyID: babyID, userID: userID, key: key)
        #expect(SealedLog.openName(sealed, babyID: babyID, userID: userID, key: key) == "Annette")
        #expect(SealedLog.openName(sealed, babyID: babyID, userID: UUID(), key: key) == nil)

        let member = MemberDTO(babyID: babyID, userID: userID, role: "caregiver", displayName: "", joinedAt: .now,
                               sealedName: sealed)
        #expect(SealedSync.openNames([member], babyID: babyID, key: key).first?.displayName == "Annette")
    }

    // MARK: Phrase-locked keys

    @Test func thePhraseUnlocksTheKeyHoweverItsTyped() throws {
        let wrapped = try SealedLog.lock(key, babyID: babyID, phrase: phrase)
        let typed = RecoveryKey.formatted(phrase).lowercased()
        let unlocked = try SealedLog.unlock(wrapped, babyID: babyID, phrase: typed)
        #expect(unlocked == key)
        #expect(throws: SealedLog.Failure.cannotOpen) {
            try SealedLog.unlock(wrapped, babyID: babyID, phrase: RecoveryKey.generate())
        }
        #expect(throws: SealedLog.Failure.cannotOpen) { try SealedLog.unlock(wrapped, babyID: UUID(), phrase: phrase) }
    }

    @Test func theServersHashOfThePhraseIsNotTheKeyItMakes() {
        let hash = RecoveryKey.hash(phrase)
        let made = SealedLog.phraseKey(phrase).withUnsafeBytes { Data($0) }.map { String(format: "%02x", $0) }.joined()
        #expect(hash != made)
    }

    // MARK: The link

    @Test func theKeyRidesTheShareLinkAndComesBackExactly() throws {
        let text = BabyKey.linkText(key)
        #expect(text.count == 43)
        #expect(!text.contains("+") && !text.contains("/") && !text.contains("="))
        #expect(BabyKey.fromLinkText(text) == key)

        let server = try #require(URL(string: "https://babyfeed.example.org:4443"))
        let link = try #require(SyncLink.url(code: "D8WAQK", server: server, key: text))
        let invitation = try #require(SyncLink.invitation(from: link))
        #expect(invitation.key == text)
        #expect(invitation.server == server)
    }

    @Test func aJunkKeyInALinkIsDroppedAndAReadableLinkHasNone() throws {
        let server = try #require(URL(string: "https://babyfeed.example.org:4443"))
        let junk = try #require(URL(string: "babyfeed://join?code=D8WAQK&server=\(server.absoluteString)&key=nope"))
        #expect(SyncLink.invitation(from: junk)?.key == nil)
        let plain = try #require(SyncLink.url(code: "D8WAQK", server: server))
        #expect(SyncLink.invitation(from: plain)?.key == nil)
        #expect(BabyKey.fromLinkText("") == nil)
    }

    @Test func joiningIsOnlyEverThroughThePublicAddress() throws {
        // An older build's link, naming the home network, isn't followed.
        let home = try #require(URL(string: "babyfeed://join?code=D8WAQK&server=http%3A%2F%2Fmini.local%3A8791"))
        #expect(SyncLink.invitation(from: home) == nil)
        #expect(SyncLink.code(from: home) == "D8WAQK", "the code alone can still join through the public address")
        let lan = try #require(URL(string: "babyfeed://join?code=D8WAQK&server=http%3A%2F%2F192.168.1.20%3A8791"))
        #expect(SyncLink.invitation(from: lan) == nil)
    }

    // MARK: Away from home

    @Test func thePublicAddressIsHTTPSOnly() {
        #expect(ServerConfig.publicURL(from: ["PublicHost": "babyfeed.example.org:4443"])?.absoluteString
                == "https://babyfeed.example.org:4443")
        #expect(ServerConfig.publicURL(from: [:]) == nil)
        #expect(ServerConfig.publicURL(from: ["PublicHost": "$(BABYFEED_PUBLIC_HOST)"]) == nil)
    }

    @Test func healthTakesAnHTTPSPublicAddressAndNothingElse() throws {
        let https = #"{"ok":true,"service":"babyfeed-server","features":["sealed"],"public_url":"https://babyfeed.example.org:4443"}"#
        let health = try SyncClient.decoder.decode(SyncClient.Health.self, from: Data(https.utf8))
        #expect(health.publicURL?.absoluteString == "https://babyfeed.example.org:4443")
        #expect(health.supportsSealed)

        let http = #"{"ok":true,"service":"babyfeed-server","features":[],"public_url":"http://babyfeed.example.org"}"#
        let refused = try SyncClient.decoder.decode(SyncClient.Health.self, from: Data(http.utf8))
        #expect(refused.publicURL == nil)
        #expect(!refused.supportsSealed)
    }

    @Test func aSealedMembershipCarriesItsLockedKey() throws {
        let json = """
        {"id":"\(babyID.uuidString)","name":"","role":"owner","updated_at":"2026-10-08T10:00:00.000Z",
         "sealed":true,"wrapped_key":"abc","sealed_name":null}
        """
        let membership = try SyncClient.decoder.decode(MembershipDTO.self, from: Data(json.utf8))
        #expect(membership.isSealed)
        #expect(membership.wrappedKey == "abc")
        #expect(membership.baby.sealed == true)

        let old = #"{"id":"\#(babyID.uuidString)","name":"Theo","role":"owner","updated_at":"2026-10-08T10:00:00.000Z"}"#
        #expect(try SyncClient.decoder.decode(MembershipDTO.self, from: Data(old.utf8)).isSealed == false)
    }

    // MARK: Only new babies

    @Test func babiesAddedNowAreSealedAndOnesFromBeforeAreNot() throws {
        let container = try AppSchema.inMemoryContainer()
        let context = container.mainContext
        let before = Baby(name: "Theo", birthDate: nil)
        context.insert(before)
        #expect(!before.isSealed, "a baby that existed already stays readable on the server")

        let added = BabyStore.addBaby(name: "Nora", birthDate: nil, in: context)
        #expect(added.isSealed)
        let created = BabyStore.createBaby(name: "Ivy", birthDate: nil, in: context)
        #expect(created.isSealed)
    }

    @Test func aBlankReadableBabyNeverOverwritesASealedOnesName() throws {
        let blank = BabyDTO(id: babyID, name: "", birthDate: nil, sex: nil, dueDate: nil, createdBy: nil,
                            updatedAt: .now.addingTimeInterval(60), deletedAt: nil, serverUpdatedAt: nil, sealed: true)
        let encoded = try SyncClient.encoder.encode(blank)
        let text = String(decoding: encoded, as: UTF8.self)
        #expect(text.contains("\"sealed\":true"))
        let readable = BabyDTO(baby: Baby(name: "Theo", birthDate: nil), createdBy: nil)
        #expect(!String(decoding: try SyncClient.encoder.encode(readable), as: UTF8.self).contains("sealed"),
                "a readable baby goes up exactly as before")
    }
}
