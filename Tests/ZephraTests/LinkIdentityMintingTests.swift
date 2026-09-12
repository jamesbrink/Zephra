import Foundation
import Synchronization
import Testing
import ZephraLinkHost
import ZephraLinkProtocol

@testable import Zephra

/// Making this Mac a new link identity, and the one case where that is a loss rather than a
/// first launch.
@Suite("Minting a link identity over pairings that are still there is said out loud")
struct LinkIdentityMintingTests {
    /// A store with whatever a test says is on disk, and a record of what was written.
    private nonisolated final class Store: LinkSecretStore, Sendable {
        private let state: Mutex<(identity: Data?, devices: [PairedDevice])>

        init(identity: Data?, devices: [PairedDevice] = []) {
            state = Mutex((identity, devices))
        }

        func identityBytes() throws -> Data? { state.withLock { $0.identity } }

        func writeIdentity(_ bytes: Data) throws { state.withLock { $0.identity = bytes } }

        func load() throws -> [PairedDevice] { state.withLock { $0.devices } }

        func save(_ devices: [PairedDevice]) throws { state.withLock { $0.devices = devices } }

        func removeAll() throws { state.withLock { $0 = (nil, []) } }

        var storedIdentity: Data? { state.withLock { $0.identity } }
    }

    private func device(_ name: String) -> PairedDevice {
        PairedDevice(
            keys: DeviceIdentity().publicKeys, name: name,
            pairedAt: Date(timeIntervalSince1970: 1), lastSeen: nil)
    }

    @Test("a Mac whose identity has gone while phones are still paired says so and still mints")
    func mintingOverPairingsIsReported() throws {
        let store = Store(identity: nil, devices: [device("A Phone"), device("Another Phone")])
        var reported: [String] = []

        let identity = try store.identity { reported.append($0) }

        #expect(store.storedIdentity == identity.rawRepresentation)
        #expect(reported.count == 1)
        #expect(reported.first?.contains("2 paired device(s)") == true)
        // There is no way back, so it mints: what it must not do is mint in silence.
        #expect(reported.first?.contains("paired again") == true)
    }

    @Test("a genuinely first launch mints in silence, because nothing was lost")
    func aFirstLaunchIsQuiet() throws {
        let store = Store(identity: nil)
        var reported: [String] = []

        _ = try store.identity { reported.append($0) }

        #expect(reported.isEmpty)
        #expect(store.storedIdentity != nil)
    }

    @Test("an identity that is there is the one that is used, whatever else is stored")
    func aStoredIdentityAlwaysWins() throws {
        let stored = DeviceIdentity()
        let store = Store(identity: stored.rawRepresentation, devices: [device("A Phone")])
        var reported: [String] = []

        let identity = try store.identity { reported.append($0) }

        #expect(identity.publicKeys == stored.publicKeys)
        #expect(reported.isEmpty)
    }
}
