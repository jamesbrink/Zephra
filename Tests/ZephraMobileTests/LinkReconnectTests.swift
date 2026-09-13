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

    @Test("pairing after an unpaired launch starts the loop")
    func anUnpairedLaunchLeavesTheLoopStartable() async throws {
        let client = client(pairedTo: nil)
        let reconnect = LinkReconnect(client: client)
        reconnect.begin()
        // The loop takes itself down rather than sitting there with nothing to dial, so
        // `isRunning` tells the truth and the `begin()` the root makes when a Mac is paired
        // is not a no-op for the rest of the launch.
        try await settle { !reconnect.isRunning }
        #expect(!reconnect.isRunning)
        reconnect.begin()
        #expect(reconnect.isRunning)
        reconnect.end()
    }

    @Test("a background flip while a retry is settling still closes the session")
    func endingUnderARetrySurvives() async throws {
        let client = client(pairedTo: host())
        let reconnect = LinkReconnect(client: client)
        reconnect.begin()
        try await settle { reconnect.nextAttemptAt != nil }
        // Retry Now leaves the cancelled loop to be waited on, and the app goes away before the
        // loop that replaced it has got past that wait: the disconnect `end()` installs must be
        // what the next `begin()` waits on, not something the resuming loop cleared away.
        reconnect.retryNow()
        reconnect.end()
        #expect(!reconnect.isRunning)
        try await settle { client.connection == .offline }
        #expect(client.connection == .offline)
        // And the app coming back still runs, on the far side of that disconnect.
        reconnect.begin()
        try await settle { client.connection.hasFailed }
        reconnect.end()
    }

    @Test("no road opening leaves a sentence up and another attempt scheduled")
    func retriesAfterAFailure() async throws {
        let client = client(pairedTo: host())
        let reconnect = LinkReconnect(client: client)
        reconnect.begin()
        try await settle { client.connection.hasFailed }
        #expect(client.connection.reason == "Zephra could not reach halcyon.")
        // The loop is still there, waiting out `LinkBackoff` before it tries again.
        #expect(reconnect.isRunning)
        reconnect.end()
    }

    @Test("no road opening says when the next attempt is")
    func saysWhenTheNextAttemptIs() async throws {
        let client = client(pairedTo: host())
        let reconnect = LinkReconnect(client: client)
        reconnect.begin()
        try await settle { client.connection.nextAttempt != nil }
        // The sentence the failure carried is kept: it is still why nothing is connected.
        #expect(client.connection.reason == "Zephra could not reach halcyon.")
        let due = try #require(reconnect.nextAttemptAt)
        #expect(due == client.connection.nextAttempt)
        // The first backoff includes bounded jitter to spread concurrent host reconnects.
        #expect(due.timeIntervalSinceNow <= 1.36) // One-second backoff plus up to 350 ms per-host jitter.
        reconnect.end()
    }

    @Test("Retry now dials before the wait is up")
    func retryingNowDialsAtOnce() async throws {
        let client = client(pairedTo: host())
        let reconnect = LinkReconnect(client: client)
        reconnect.begin()
        try await settle { reconnect.nextAttemptAt != nil }
        // The wait goes the moment it is skipped, and a fresh one is scheduled by the attempt
        // that follows — inside the second the loop would otherwise have been sitting out.
        reconnect.retryNow()
        #expect(reconnect.nextAttemptAt == nil)
        try await settle(within: 60) { reconnect.nextAttemptAt != nil }
        #expect(reconnect.isRunning)
        reconnect.end()
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

/// Whether the client has given up on an attempt, whatever it gave up saying and whether or
/// not the next one has been scheduled yet: the two are a moment apart, and no assertion here
/// is about which side of that moment the poll landed on.
extension LinkConnectionState {
    fileprivate var hasFailed: Bool {
        switch self {
        case .failed, .waiting: true
        default: false
        }
    }
}
