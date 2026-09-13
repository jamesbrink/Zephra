import Foundation
import ZephraLinkClient
import ZephraLinkProtocol
@testable import ZephraMobile

/// A real encrypted client session over in-process roads, shared with the package's fake Mac.
@MainActor
final class MobileHostFixture {
    let host: FakeHost
    let client: LinkClient
    let preference: HostPreference
    init(name: String, phone: DeviceIdentity = DeviceIdentity()) {
        let host = FakeHost(pairingSecret: Data(repeating: 9, count: PairingSecret.byteCount), known: [phone.publicKeys])
        self.host = host
        let paired = PairedHost(name: name, keys: host.publicKeys,
            endpoints: [Endpoint(host: "127.0.0.1", port: 7777)],
            roomID: host.identity.roomID, pairedAt: Date())
        preference = HostPreference(host: paired)
        host.world = MobilePreview.snapshot()
        host.world?.multiHost = true
        host.world?.hostName = name
        host.publishesSnapshotOnConnect = true
        client = LinkClient(store: MemoryLinkKeyStore(identity: phone, pairedHost: paired),
            roads: MemoryLinkRoads { _ in
                let (phone, mac) = MemoryLinkConnection.pair()
                await host.serve(mac)
                return phone
            }, deviceName: "Test Phone")
    }
    static func settle(_ condition: @MainActor () -> Bool) async throws {
        let deadline = ContinuousClock.now + .seconds(5)
        while !condition() {
            guard ContinuousClock.now < deadline else { throw LinkClientError.timedOut }
            try await Task.sleep(for: .milliseconds(5))
        }
    }
    func stop() async { await client.disconnect(); await host.stop() }
}
