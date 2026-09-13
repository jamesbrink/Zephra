import Foundation
import Testing
import ZephraLinkHost
import ZephraLinkProtocol

@testable import ZephraEngine

/// What the Mac knows about when a phone was here, which is what its Devices list draws.
@MainActor
@Suite("The Mac knows which phones are here and when the others last were")
struct CompanionLastSeenTests {
    @Test("a phone with a session up is connected, and its leaving is the last it was seen")
    func aSessionEndingIsASeen() async throws {
        let bed = CompanionTestBed()
        let phone = try await bed.pairedPhone()
        _ = try await phone.snapshot()
        let device = try #require(bed.host.devices.first)
        #expect(bed.host.isConnected(device))
        let atHandshake = try #require(device.lastSeen)

        try await Task.sleep(for: .milliseconds(20))
        await phone.disconnect()
        try await bed.waitUntil { bed.host.sessions.isEmpty }

        let after = try #require(bed.host.devices.first)
        #expect(!bed.host.isConnected(after))
        #expect(try #require(after.lastSeen) > atHandshake, "the end of the session moved it")
        await bed.shutdown()
    }
}
