import Foundation
import Testing
import ZephraLinkHost
import ZephraLinkProtocol

@testable import ZephraEngine

/// How many answers one pairing code is worth, which is what makes guessing at it expensive.
@MainActor
@Suite("A pairing code is burned after three wrong answers")
struct CompanionPairingAttemptTests {
    @Test("two wrong answers leave the code up, and the third takes it down")
    func theThirdWrongAnswerEndsIt() async throws {
        let bed = CompanionTestBed()
        let payload = bed.host.beginPairing()

        try await bed.guessAtTheCode()
        try await bed.guessAtTheCode()
        #expect(bed.host.pairing?.secret == payload.secret, "two is a person with a stale screen")
        #expect(bed.host.pairingNote == nil)

        try await bed.guessAtTheCode()
        #expect(bed.host.pairing == nil, "the third is something working through answers")
        #expect(bed.host.pairingNote != nil, "and the person is told where the code went")
        #expect(bed.host.devices.isEmpty)
        await bed.shutdown()
    }

    @Test("the burned secret is gone: the code that was on screen no longer pairs")
    func theSecretIsBurned() async throws {
        let bed = CompanionTestBed()
        let payload = bed.host.beginPairing()
        for _ in 0..<CompanionHost.pairingAttemptLimit { try await bed.guessAtTheCode() }

        let (_, failure) = await bed.refusedPhone(pairingSecret: payload.secret)
        #expect(failure as? LinkError != nil, "the right answer to a burned code is refused")
        #expect(bed.host.devices.isEmpty)
        await bed.shutdown()
    }

    @Test("a fresh code clears the note and the count")
    func aFreshCodeStartsOver() async throws {
        let bed = CompanionTestBed()
        _ = bed.host.beginPairing()
        for _ in 0..<CompanionHost.pairingAttemptLimit { try await bed.guessAtTheCode() }
        #expect(bed.host.pairingNote != nil)

        let fresh = bed.host.beginPairing()
        #expect(bed.host.pairingNote == nil)
        try await bed.guessAtTheCode()
        #expect(bed.host.pairing?.secret == fresh.secret, "the count started over with the code")
        await bed.shutdown()
    }

    @Test("a phone that reads the code right still pairs, wrong answers before it or not")
    func theRightAnswerStillPairs() async throws {
        let bed = CompanionTestBed()
        let payload = bed.host.beginPairing()
        try await bed.guessAtTheCode()

        let phone = try await bed.phone(pairingSecret: payload.secret)
        _ = try await phone.snapshot()
        #expect(bed.host.devices.count == 1)
        #expect(bed.host.pairing == nil, "one code pairs one phone")
        #expect(bed.host.pairingNote == nil, "and it went because it was used, not because it failed")
        await bed.shutdown()
    }
}
