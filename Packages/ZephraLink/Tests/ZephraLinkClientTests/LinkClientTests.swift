import Foundation
import Testing
import ZephraLinkClient
import ZephraLinkProtocol

/// Pairing, reconnecting, and the refusal in between.
@MainActor
@Suite("A phone pairs with one Mac and remembers it")
struct LinkClientTests {
    @Test("pairing over a road leaves the session live and the Mac remembered")
    func pairingSucceeds() async throws {
        let bed = LinkClientUnderTest()
        defer { Task { await bed.host.stop() } }
        try await bed.client.pair(with: bed.pairingCode())
        #expect(bed.client.connection == .live(.lan))
        #expect(bed.client.pairedHost?.keys == bed.host.publicKeys)
        #expect(try bed.store.loadPairedHost()?.name == "A Mac")
    }

    @Test("a reconnection needs no secret, only the keys both ends already hold")
    func reconnectionNeedsNoSecret() async throws {
        let bed = LinkClientUnderTest(remembering: DeviceIdentity())
        defer { Task { await bed.host.stop() } }
        await bed.client.connect()
        #expect(bed.client.connection == .live(.lan))
    }

    @Test("a Mac that has never met this device refuses it in words")
    func unknownDeviceIsRefused() async throws {
        let bed = LinkClientUnderTest(remembering: DeviceIdentity(), knownToHost: false)
        defer { Task { await bed.host.stop() } }
        await bed.client.connect()
        #expect(bed.client.connection == .failed(LinkError.notPaired.reason))
    }

    @Test("a code past its time is refused before any road is opened")
    func expiredCodeIsRefused() async throws {
        let bed = LinkClientUnderTest()
        defer { Task { await bed.host.stop() } }
        let stale = PairingPayload(
            hostName: "A Mac", keys: bed.host.publicKeys, endpoints: [],
            secret: Data(repeating: 9, count: PairingSecret.byteCount),
            expiresAt: Date().addingTimeInterval(-1))
        await #expect(throws: LinkError.self) { try await bed.client.pair(with: stale) }
        #expect(bed.client.pairedHost == nil)
    }

    @Test("forgetting the Mac clears the pairing and the session")
    func forgettingClearsEverything() async throws {
        let bed = LinkClientUnderTest()
        defer { Task { await bed.host.stop() } }
        try await bed.client.pair(with: bed.pairingCode())
        await bed.client.forgetHost()
        #expect(bed.client.pairedHost == nil)
        #expect(bed.client.connection == .offline)
        #expect(try bed.store.loadPairedHost() == nil)
    }

    @Test("a frozen client shows its state and touches nothing")
    func frozenNeedsNoNetwork() async throws {
        let client = LinkClient.frozen(
            snapshot: ClientFixtures.snapshot, library: [ClientFixtures.entry("one.png")])
        #expect(client.connection == .live(.lan))
        #expect(client.snapshot?.hostName == "A Mac")
        #expect(client.library.count == 1)
        #expect(try await client.request(.cancel) == .ok)
        await #expect(throws: (any Error).self) { try await client.file(name: "one.png") }
    }
}
