import Foundation
import Testing
import ZephraLinkProtocol
@testable import ZephraLinkClient

@MainActor @Suite("A silent preview subscriber cannot delay another host")
struct PreviewDeadlineTests {
    @Test func stalledPeer() async throws {
        let stalled = LinkClientUnderTest(), healthy = LinkClientUnderTest()
        defer { Task { await stalled.client.disconnect(); await healthy.client.disconnect(); await stalled.host.stop(); await healthy.host.stop() } }
        for bed in [stalled, healthy] {
            try await bed.client.pair(with: bed.pairingCode())
            try await LinkGapRecoveryTests.settle { bed.host.isAuthenticated }
            var world = ClientFixtures.snapshot
            world.multiHost = true
            try await bed.host.announce(world, kind: .snapshot)
            try await LinkGapRecoveryTests.settle { bed.client.libraryIsComplete }
        }
        stalled.host.silentPreviews = true
        let first = Task { try? await stalled.client.setPreviews(false, timeout: .milliseconds(200)) }
        try await LinkGapRecoveryTests.settle { stalled.host.commands.contains(.multiHost(.previews(false))) }
        try await healthy.client.setPreviews(true)
        #expect(healthy.host.commands.contains(.multiHost(.previews(true))))
        #expect(!stalled.client.pending.isEmpty, "the healthy host completes while the first host is still silent")
        await first.value
        #expect(stalled.client.pending.isEmpty)
        #expect(stalled.host.commands.filter { $0 == .multiHost(.previews(false)) }.count == 1)
        #expect(healthy.client.connection.isLive && stalled.client.connection.isLive)
    }
}
