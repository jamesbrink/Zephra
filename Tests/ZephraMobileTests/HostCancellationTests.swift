import Foundation
import Testing
import ZephraLinkClient
import ZephraLinkProtocol
@testable import ZephraMobile

@MainActor @Suite("Cancelled host attempts cannot outlive their screen or foreground")
struct HostCancellationTests {
    @Test(arguments: [false, true])
    func pairing(_ background: Bool) async throws {
        let gate = HeldDial(), mac = FakeHost(pairingSecret: Data(repeating: 9, count: PairingSecret.byteCount))
        let client = LinkClient(store: MemoryLinkKeyStore(), roads: MemoryLinkRoads { _ in
            await gate.wait()
            let (phone, host) = MemoryLinkConnection.pair()
            await gate.remember(phone)
            await mac.serve(host)
            return phone
        }, deviceName: "Phone")
        let b = MobileHostFixture(name: "B")
        let hosts = HostConnections(storage: nil,
            catalog: LibraryCatalog(libraryRoot: nil, filesRoot: nil), makeClient: { _ in client })
        hosts.add(b.preference, client: b.client)
        hosts.setActive(true)
        try await MobileHostFixture.settle { b.client.supportsMultiHost }
        let payload = PairingPayload(hostName: "A", keys: mac.publicKeys,
            endpoints: [Endpoint(host: "held", port: 1)], secret: Data(repeating: 9, count: PairingSecret.byteCount),
            expiresAt: Date().addingTimeInterval(60))
        let attempt = Task { try await hosts.pair(payload) }
        await gate.started()
        if background { hosts.setActive(false) } else { hosts.cancelPairing() }
        do { try await attempt.value; Issue.record("Cancelled pairing succeeded") }
        catch is CancellationError {} catch { Issue.record("Unexpected cancellation error: \(error)") }
        await gate.release()
        try await waitForClosed(gate)
        #expect(!client.connection.isLive && client.pairedHost == nil)
        #expect(hosts.hosts.map(\.id) == [b.preference.id])
        if !background {
            #expect(b.client.supportsMultiHost)
            try await b.client.setTags(names: ["b.png"], tags: ["still usable"])
        }
        hosts.setActive(false)
        for host in hosts.hosts { await host.reconnect?.stopAndDrain() }
        await b.stop(); await mac.stop()
    }
    @Test func reconnectInProgress() async throws {
        let gate = HeldDial(), identity = DeviceIdentity(), phone = DeviceIdentity()
        let paired = PairedHost(name: "A", keys: identity.publicKeys,
            endpoints: [Endpoint(host: "held", port: 1)], roomID: identity.roomID, pairedAt: Date())
        let client = LinkClient(store: MemoryLinkKeyStore(identity: phone, pairedHost: paired),
            roads: MemoryLinkRoads { _ in
                await gate.wait()
                let (road, _) = MemoryLinkConnection.pair()
                await gate.remember(road)
                return road
            }, deviceName: "Phone")
        let reconnect = LinkReconnect(client: client)
        reconnect.begin()
        await gate.started()
        await reconnect.stopAndDrain()
        await gate.release()
        try await waitForClosed(gate)
        #expect(!reconnect.isRunning && !client.connection.isLive)
        #expect(client.pairedHost?.keys == paired.keys)
    }
    private func waitForClosed(_ gate: HeldDial) async throws {
        let deadline = ContinuousClock.now + .seconds(3)
        while !(await gate.closed) {
            guard ContinuousClock.now < deadline else { throw LinkClientError.timedOut }
            try await Task.sleep(for: .milliseconds(5))
        }
    }
}

private actor HeldDial {
    private var waiting: CheckedContinuation<Void, Never>?
    private var start: CheckedContinuation<Void, Never>?
    private var hasStarted = false
    private var road: MemoryLinkConnection?
    var closed: Bool { road?.isOpen == false }
    func wait() async {
        hasStarted = true; start?.resume(); start = nil
        await withCheckedContinuation { waiting = $0 }
    }
    func started() async {
        if !hasStarted { await withCheckedContinuation { start = $0 } }
    }
    func release() { waiting?.resume(); waiting = nil }
    func remember(_ road: MemoryLinkConnection) { self.road = road }
}
