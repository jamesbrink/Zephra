import Foundation
import Testing
import ZephraLinkProtocol
import ZephraLinkTransport

@testable import ZephraLinkClient

/// Roads where nothing local answers and the relay says what the test says.
private final class RefusingRoads: LinkRoads, @unchecked Sendable {
    private let relayAnswer: any Error

    init(relay: any Error) {
        relayAnswer = relay
    }

    func browse() -> AsyncStream<[LinkCandidate]> {
        AsyncStream { $0.finish() }
    }

    func connect(_ candidate: LinkCandidate) async throws -> any LinkConnection {
        throw LinkClientError.unreachable
    }

    func connectLAN(_ endpoint: Endpoint) async throws -> any LinkConnection {
        throw LinkClientError.unreachable
    }

    func connectRelay(room: RoomID, pairing: Bool) async throws -> any LinkConnection {
        throw relayAnswer
    }
}

/// What the relay turning this phone away is worth, which is not the same thing as the Mac
/// turning it away.
@MainActor
@Suite("The relay refusing a phone is not the Mac withdrawing a pairing")
struct LinkRelayRefusalTests {
    private func client(over roads: any LinkRoads) -> (LinkClient, MemoryLinkKeyStore) {
        let store = MemoryLinkKeyStore(
            identity: DeviceIdentity(),
            pairedHost: PairedHost(
                name: "A Mac", keys: DeviceIdentity().publicKeys, endpoints: [],
                roomID: DeviceIdentity().roomID, pairedAt: Date()))
        return (LinkClient(store: store, roads: roads, deviceName: "A Phone"), store)
    }

    @Test("a relay that says not allowed on a reconnect does not forget the Mac")
    func aRelayRefusalOnReconnectKeepsTheMac() async throws {
        let (client, store) = client(over: RefusingRoads(relay: LinkClientError.notAdmitted))

        await client.connect()

        // The Mac's list is a moment out of date — it restarted, or joined its room before it
        // read its own pairings. Forgetting it here would cost a code to get back a Mac that
        // withdrew nothing.
        #expect(client.pairedHost != nil)
        #expect(try store.loadPairedHost() != nil)
        #expect(client.farewell == nil)
        #expect(!client.connection.isLive)
    }

    @Test("the Mac's own refusal on a reconnect still lets the Mac go")
    func theMacsOwnRefusalStillUnpairs() async throws {
        let (client, store) = client(over: RefusingRoads(relay: LinkError.notPaired))

        await client.connect()

        #expect(client.pairedHost == nil)
        #expect(try store.loadPairedHost() == nil)
        #expect(client.farewell != nil)
    }

    @Test("the road tells the two apart by what the phone was doing")
    func theRoadMapsNotAllowedByWhatItWasDoing() {
        let refusal = RelayError.refused(RelayError.notAllowed)
        // Reading a code, the person is owed the Mac's sentence and the walk of the roads stops.
        #expect(NetworkLinkRoads.failure(for: refusal, pairing: true) as? LinkError == .notPaired)
        // Reconnecting, it is a wait.
        #expect(
            NetworkLinkRoads.failure(for: refusal, pairing: false) as? LinkClientError
                == .notAdmitted)
        // The refusals about the moment are unchanged either way.
        #expect(
            NetworkLinkRoads.failure(for: .refused("no host"), pairing: false) as? LinkClientError
                == .unreachable)
    }
}
