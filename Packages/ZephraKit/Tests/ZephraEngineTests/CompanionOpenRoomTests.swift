import Foundation
import Testing
import ZephraLinkProtocol

@testable import ZephraEngine
@testable import ZephraLinkHost

/// When this Mac tells the relay its room is open, which is only while a code is on screen.
///
/// A phone pairing for the first time holds a key that is on no allow-list — it cannot be, the
/// pairing is what puts it there — so a relay that admitted only listed keys refused the one
/// guest the code was put up for. The room is open for exactly as long as the code is, and it
/// buys a stranger a handshake it still cannot pass.
@MainActor
@Suite("The relay room is open only while a pairing code is showing")
struct CompanionOpenRoomTests {
    @Test("a Mac with no code up keeps its room shut")
    func noCodeMeansAShutRoom() async throws {
        let bed = CompanionTestBed()
        #expect(!bed.host.relayOpen)
        await bed.shutdown()
    }

    @Test("showing a code opens the room and taking it down shuts it")
    func aCodeOpensAndClosesTheRoom() async throws {
        let bed = CompanionTestBed()
        bed.host.beginPairing()
        #expect(bed.host.relayOpen)
        bed.host.endPairing()
        #expect(!bed.host.relayOpen)
        await bed.shutdown()
    }

    @Test("a pairing that succeeds shuts the room with the code")
    func pairingShutsTheRoom() async throws {
        let bed = CompanionTestBed()
        let phone = try await bed.pairedPhone()
        _ = try await phone.snapshot()

        #expect(bed.host.devices.count == 1)
        #expect(!bed.host.relayOpen, "the code is spent, so the room is no longer open")
        #expect(bed.host.relayAllowList == [phone.identity.publicKeys.signing])
        await bed.shutdown()
    }

    @Test("three wrong answers shut the room along with the code")
    func guessingShutsTheRoom() async throws {
        let bed = CompanionTestBed()
        bed.host.beginPairing()
        for _ in 0..<CompanionHost.pairingAttemptLimit { try await bed.guessAtTheCode() }

        #expect(bed.host.pairing == nil)
        #expect(!bed.host.relayOpen)
        await bed.shutdown()
    }

    @Test("a code that simply runs out shuts the room on its own")
    func anExpiredCodeShutsTheRoom() async throws {
        let bed = CompanionTestBed()
        bed.host.openRoom(until: Date().addingTimeInterval(0.02))
        #expect(bed.host.relayOpen)
        try await bed.waitUntil { !bed.host.relayOpen }
        await bed.shutdown()
    }

    @Test("stopping the host shuts the room")
    func stoppingShutsTheRoom() async throws {
        let bed = CompanionTestBed()
        bed.host.beginPairing()
        await bed.host.stop()
        #expect(!bed.host.relayOpen)
        await bed.shutdown()
    }
}
