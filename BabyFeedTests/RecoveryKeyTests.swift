import Foundation
import Testing
@testable import BabyFeed

/// The recovery key has to survive being written on paper and typed back in
/// by somebody who hasn't slept, and it has to hash to exactly what the server
/// stored. Both halves are here, because getting either wrong turns the
/// backstop into a dead end at the worst possible moment.
struct RecoveryKeyTests {
    @Test func aKeyIsTwentyFourCharactersFromASafeAlphabet() {
        let key = RecoveryKey.generate()
        #expect(key.count == RecoveryKey.length)
        #expect(RecoveryKey.isPlausible(key))

        // No character anybody has to squint at.
        #expect(!key.contains("I"))
        #expect(!key.contains("O"))
        #expect(!key.contains("0"))
        #expect(!key.contains("1"))
    }

    @Test func twoKeysAreNotTheSame() {
        let keys = Set((0..<64).map { _ in RecoveryKey.generate() })
        #expect(keys.count == 64)
    }

    @Test func itIsShownInGroupsOfFour() {
        let formatted = RecoveryKey.formatted("ABCDEFGHJKLMNPQRSTUVWXYZ")
        #expect(formatted == "ABCD-EFGH-JKLM-NPQR-STUV-WXYZ")
        #expect(formatted.filter { $0 == "-" }.count == RecoveryKey.groupCount - 1)
    }

    @Test func howAPersonTypesItBackStillCounts() {
        let key = RecoveryKey.generate()
        let written = RecoveryKey.formatted(key)

        for attempt in [written, written.lowercased(), written.replacingOccurrences(of: "-", with: " "),
                        " \(written) ", written.replacingOccurrences(of: "-", with: "")] {
            #expect(RecoveryKey.isPlausible(attempt), "\(attempt) should be accepted")
            #expect(RecoveryKey.normalized(attempt) == key)
            #expect(RecoveryKey.hash(attempt) == RecoveryKey.hash(key),
                    "however it's typed, it must hash to what the server stored")
        }
    }

    @Test func nearMissesAreRejectedRatherThanSentToTheServer() {
        let key = RecoveryKey.generate()
        #expect(!RecoveryKey.isPlausible(String(key.dropLast())))
        #expect(!RecoveryKey.isPlausible(key + "A"))
        #expect(!RecoveryKey.isPlausible(""))
        // I and O are exactly the characters someone mis-copies for 1 and 0.
        #expect(!RecoveryKey.isPlausible(String(repeating: "I", count: RecoveryKey.length)))
        #expect(!RecoveryKey.isPlausible(String(repeating: "O", count: RecoveryKey.length)))
    }

    @Test func theHashIsSHA256HexOfTheNormalisedKey() {
        let hash = RecoveryKey.hash("ABCD-EFGH-JKLM-NPQR-STUV-WXYZ")
        #expect(hash.count == 64)
        #expect(hash.allSatisfy { $0.isHexDigit && !$0.isUppercase })
        #expect(hash == RecoveryKey.hash("abcdefghjklmnpqrstuvwxyz"))
    }

    /// The one thing neither side's own tests can catch: the phone hashing a
    /// key one way and the server hashing it another. This digest was produced
    /// by the server's own code path — createHash('sha256') over
    /// normalizeRecoveryKey(...) — so if either end ever drifts, a key written
    /// on paper stops opening the log and this fails instead.
    @Test func theHashMatchesWhatTheServerComputes() {
        #expect(RecoveryKey.hash("ABCD-EFGH-JKLM-NPQR-STUV-WXYZ")
                == "f1c7e627a0350672d6914ca90d0e75f0295b1ce2ceb658cca136f7c46fd6eb64")
    }
}
