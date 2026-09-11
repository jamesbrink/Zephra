import Foundation
import Testing
import ZephraLinkHost
import ZephraLinkProtocol

@testable import ZephraEngine

/// What the Mac tells the relay it will admit, which is the whole of the relay's own check.
@MainActor
@Suite("The Mac's relay allow-list is its paired devices")
struct CompanionAllowListTests {
    @Test("a Mac that has paired nothing admits nobody")
    func nothingPairedAdmitsNobody() async throws {
        let bed = CompanionTestBed()
        #expect(bed.host.relayAllowList.isEmpty)
        await bed.shutdown()
    }

    @Test("a paired phone's signing key is on the list, and a revoked one is not")
    func pairingPutsAKeyOnTheList() async throws {
        let bed = CompanionTestBed()
        let phone = try await bed.pairedPhone()
        _ = try await phone.snapshot()

        #expect(bed.host.relayAllowList == [phone.identity.publicKeys.signing])
        let device = try #require(bed.host.devices.first)
        await bed.host.revoke(device)
        #expect(bed.host.relayAllowList.isEmpty)
        await bed.shutdown()
    }

    @Test("more phones than the relay takes keeps the ones most recently seen")
    func theListIsTrimmedToTheRecentlySeen() async throws {
        let bed = CompanionTestBed()
        let now = Date()
        let devices = (0..<20).map { index in
            PairedDevice(
                keys: DevicePublicKeys(
                    keyAgreement: Data(repeating: UInt8(index), count: 32),
                    signing: Data(repeating: UInt8(100 + index), count: 32)),
                name: "Phone \(index)", pairedAt: now,
                lastSeen: now.addingTimeInterval(Double(index)))
        }
        try bed.pairings.save(devices)
        let host = CompanionHost(
            store: bed.store, index: bed.index, thumbnails: bed.thumbnails,
            identity: bed.identity, pairings: bed.pairings, hostName: "A Test Mac")

        #expect(host.relayAllowList.count == RelayJoin.allowLimit)
        #expect(host.relayAllowList.first == devices.last?.keys.signing, "newest first")
        #expect(!host.relayAllowList.contains(devices[0].keys.signing), "the oldest falls off")
        await bed.shutdown()
    }
}
