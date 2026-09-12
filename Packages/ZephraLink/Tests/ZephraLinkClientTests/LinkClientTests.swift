import Foundation
import Testing
@testable import ZephraLinkClient
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

    @Test("a Mac that no longer knows this phone is let go on reconnect, with the reason kept")
    func revokedMacIsForgottenOnReconnect() async throws {
        let bed = LinkClientUnderTest(remembering: DeviceIdentity(), knownToHost: false)
        defer { Task { await bed.host.stop() } }
        await bed.client.connect()
        #expect(bed.client.pairedHost == nil)
        #expect(try bed.store.loadPairedHost() == nil)
        #expect(bed.client.farewell == "A Mac no longer shares with this phone. Pair again with a new code.")
        #expect(!bed.client.connection.isLive)
    }

    @Test("a revocation on a live session ends it, forgets the Mac and keeps the Mac's words")
    func revokedOnLiveSession() async throws {
        let bed = LinkClientUnderTest(remembering: DeviceIdentity())
        defer { Task { await bed.host.stop() } }
        await bed.client.connect()
        #expect(bed.client.connection == .live(.lan))
        // The Mac's channel opens on the confirm, a frame behind the phone going live.
        for attempt in 0..<50 {
            do {
                try await bed.host.announce(
                    LinkError(code: .revoked, reason: "This Mac has stopped sharing with this device."),
                    kind: .error)
                break
            } catch {
                try #require(attempt < 49, "the Mac never opened its channel")
                try await Task.sleep(for: .milliseconds(20))
            }
        }
        for _ in 0..<50 where bed.client.pairedHost != nil {
            try await Task.sleep(for: .milliseconds(20))
        }
        #expect(bed.client.pairedHost == nil)
        #expect(bed.client.farewell == "This Mac has stopped sharing with this device.")
        #expect(!bed.client.connection.isLive)
    }

    @Test("pairing again clears the words of the last revocation")
    func pairingClearsFarewell() async throws {
        let bed = LinkClientUnderTest()
        defer { Task { await bed.host.stop() } }
        await bed.client.unpair(saying: "gone")
        try await bed.client.pair(with: bed.pairingCode())
        #expect(bed.client.farewell == nil)
    }

    @Test("a Mac with no code up says only that it has not paired this phone, plus what to check")
    func pairingWithNoCodeUpSaysWhatToCheck() async throws {
        // The Mac's answer is the same sentence whether the key is unknown or the code has come
        // down — deliberately. The pairing screen adds the half a person can act on.
        let bed = LinkClientUnderTest(secret: nil)
        defer { Task { await bed.host.stop() } }
        await #expect(throws: LinkError.self) { try await bed.client.pair(with: bed.pairingCode()) }

        guard case .failed(let shown) = bed.client.connection else {
            return #expect(Bool(false), "a refused pairing is a failed connection")
        }
        #expect(shown.hasPrefix(LinkError.notPaired.reason))
        #expect(shown.contains("Check that the code is still showing on your Mac"))
        #expect(bed.client.pairedHost == nil)
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
