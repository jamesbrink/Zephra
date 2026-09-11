import Foundation
import ZephraCore
import ZephraLinkHost
import ZephraLinkProtocol

@testable import ZephraEngine

/// A Mac and the road a phone reaches it on, over `EngineTestBed`'s store and index.
///
/// Everything goes through the host's public door — a listener is served, a connection is
/// offered to it — so the suites exercise the same path the app's TCP listener will.
@MainActor
final class CompanionTestBed {
    let engine = EngineTestBed()
    let listener = MemoryLinkListener()
    let pairings = MemoryPairingStore()
    let thumbnails = StubThumbnails()
    let identity = DeviceIdentity()
    let store: GenerationStore
    let index: LibraryIndex
    let host: CompanionHost

    init(hostName: String = "A Test Mac") {
        store = engine.store()
        index = engine.index()
        host = CompanionHost(
            store: store, index: index, thumbnails: thumbnails, identity: identity,
            pairings: pairings, hostName: hostName,
            endpoints: { [Endpoint(host: "192.168.1.2", port: 7890)] })
        host.serve(listener)
    }

    /// The Mac's published keys, which a phone needs before it can knock.
    var keys: DevicePublicKeys { identity.publicKeys }

    /// A phone on a fresh road to this Mac, connected and past its handshake.
    func phone(
        identity: DeviceIdentity = DeviceIdentity(),
        named name: String = "A Test iPhone",
        pairingSecret: Data? = nil
    ) async throws -> FakePhone {
        let (macSide, phoneSide) = MemoryLinkConnection.pair()
        let phone = FakePhone(connection: phoneSide, identity: identity, deviceName: name)
        listener.offer(macSide)
        try await phone.connect(to: keys, pairingSecret: pairingSecret)
        return phone
    }

    /// A phone that has just read a code off the screen and paired with it.
    func pairedPhone(
        identity: DeviceIdentity = DeviceIdentity(), named name: String = "A Test iPhone"
    ) async throws -> FakePhone {
        let payload = host.beginPairing()
        return try await phone(identity: identity, named: name, pairingSecret: payload.secret)
    }

    /// A phone on a road this Mac has taken, without waiting for the handshake to succeed —
    /// for the cases where it must not.
    func refusedPhone(
        identity: DeviceIdentity = DeviceIdentity(), pairingSecret: Data? = nil
    ) async -> (phone: FakePhone, failure: (any Error)?) {
        let (macSide, phoneSide) = MemoryLinkConnection.pair()
        let phone = FakePhone(connection: phoneSide, identity: identity)
        listener.offer(macSide)
        do {
            try await phone.connect(to: keys, pairingSecret: pairingSecret)
            return (phone, nil)
        } catch {
            return (phone, error)
        }
    }

    /// One wrong answer to the code on screen, from a device the Mac has never met.
    func guessAtTheCode() async throws {
        let (macSide, phoneSide) = MemoryLinkConnection.pair()
        let phone = FakePhone(connection: phoneSide, identity: DeviceIdentity())
        listener.offer(macSide)
        try await phone.guessTheCode(of: keys)
        // The Mac reads the confirm on a task of its own, so the guess is not counted until the
        // session it arrived on has gone.
        try await waitUntil { host.sessions.isEmpty }
    }

    /// Brings the store up with the mock backend loaded and no warm-up.
    func bootstrap() async {
        store.warmsUpAfterLoad = false
        await store.bootstrap()
    }

    /// Blocks until `condition` holds, so a test waits on the Mac's own timing rather than on a
    /// sleep it guessed at.
    func waitUntil(_ condition: () -> Bool) async throws {
        let deadline = ContinuousClock.now + FakePhone.patience
        while !condition() {
            guard ContinuousClock.now < deadline else { throw FakePhone.LinkFailure.timedOut }
            try await Task.sleep(for: .milliseconds(2))
        }
    }

    func shutdown() async {
        await host.stop()
        await store.shutdown()
        await index.shutdown()
    }
}
