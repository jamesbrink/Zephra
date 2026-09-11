import Foundation
import Testing
import ZephraLinkClient
import ZephraLinkProtocol

@testable import ZephraMobile

/// The phone's reconnection policy: what it does with a Mac it already knows, what it does when
/// no road to that Mac opens, and what it does when the app goes away.
///
/// A client over `MemoryLinkRoads` and `MemoryLinkKeyStore`, which is the whole point of those
/// two being protocols — no keychain, no socket, and no permission dialog for the local network.
/// No fake Mac is stood up here: both cases this suite is about happen before a handshake would,
/// and the handshake itself is pinned in `ZephraLinkClientTests`.
@MainActor
@Suite("The phone keeps itself connected while it is in front of somebody")
struct LinkReconnectTests {
    /// A Mac this phone has met, as the store would hand it back.
    private func host() -> PairedHost {
        PairedHost(
            name: "halcyon", keys: DeviceIdentity().publicKeys,
            endpoints: [Endpoint(host: "192.168.1.20", port: 52_311)],
            roomID: DeviceIdentity().roomID, pairedAt: Date(timeIntervalSince1970: 1_789_040_400))
    }

    /// A client that knows that Mac, and roads that never open.
    private func client(pairedTo host: PairedHost?) -> LinkClient {
        LinkClient(
            store: MemoryLinkKeyStore(identity: DeviceIdentity(), pairedHost: host),
            roads: MemoryLinkRoads { _ in throw LinkClientError.unreachable },
            deviceName: "A Phone")
    }

    @Test("the Mac paired last time is known before anything is connected")
    func restoresThePairedHost() {
        let known = host()
        let client = client(pairedTo: known)
        #expect(client.pairedHost == known)
        #expect(client.connection == .offline)
    }

    @Test("a phone that has never paired knows no Mac, and the pairing screen is what that is")
    func remembersNothingWhenNothingWasPaired() {
        #expect(client(pairedTo: nil).pairedHost == nil)
    }

    @Test("a launch with no Mac paired tries nothing at all")
    func staysPutWithNoMac() async throws {
        let client = client(pairedTo: nil)
        let reconnect = LinkReconnect(client: client)
        reconnect.begin()
        try await Task.sleep(for: .milliseconds(50))
        #expect(client.connection == .offline)
    }

    @Test("no road opening leaves a sentence up and another attempt scheduled")
    func retriesAfterAFailure() async throws {
        let client = client(pairedTo: host())
        let reconnect = LinkReconnect(client: client)
        reconnect.begin()
        try await settle { client.connection.hasFailed }
        #expect(client.connection == .failed("Zephra could not reach halcyon."))
        // The loop is still there, waiting out `LinkBackoff` before it tries again.
        #expect(reconnect.isRunning)
    }

    @Test("going to the background stops the trying and closes the session")
    func backgroundingCancelsTheRetry() async throws {
        let client = client(pairedTo: host())
        let reconnect = LinkReconnect(client: client)
        reconnect.begin()
        try await settle { client.connection.hasFailed }
        reconnect.end()
        #expect(!reconnect.isRunning)
        try await settle { client.connection == .offline }
        #expect(client.connection == .offline)
    }

    @Test("coming to the front twice does not open two roads")
    func beginningTwiceRunsOneLoop() async throws {
        let client = client(pairedTo: host())
        let reconnect = LinkReconnect(client: client)
        reconnect.begin()
        reconnect.begin()
        try await settle { client.connection.hasFailed }
        #expect(reconnect.isRunning)
        reconnect.end()
    }

    /// Waits for something the loop does on its own, rather than for a length of time.
    ///
    /// - Parameter condition: what the loop is expected to get the client to.
    private func settle(
        within limit: Int = 200, until condition: @MainActor () -> Bool
    ) async throws {
        for _ in 0..<limit {
            if condition() { return }
            try await Task.sleep(for: .milliseconds(10))
        }
        Issue.record("the client never got there")
    }
}

/// Whether the client has given up on an attempt, whatever it gave up saying.
extension LinkConnectionState {
    fileprivate var hasFailed: Bool { if case .failed = self { true } else { false } }
}
