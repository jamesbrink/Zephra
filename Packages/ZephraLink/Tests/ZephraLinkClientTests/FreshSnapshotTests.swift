import Foundation
import Testing
import ZephraLinkProtocol
@testable import ZephraLinkClient

@MainActor @Suite("Cached capability flags never negotiate a new connection")
struct FreshSnapshotTests {
    @Test("A connected client waits for this session's snapshot before sending new commands")
    func cachedFlagIsNotPermission() async throws {
        let bed = LinkClientUnderTest()
        defer { Task { await bed.client.disconnect(); await bed.host.stop() } }
        var world = ClientFixtures.snapshot
        world.multiHost = true
        bed.client.snapshot = world
        try await bed.client.pair(with: bed.pairingCode())
        #expect(bed.client.connection.isLive)
        #expect(!bed.client.hasFreshSnapshot)
        #expect(bed.client.authenticatedSessionID == nil)
        #expect(!bed.client.supportsMultiHost)
        let job = StrictGeneration(request: GenerationRequest(modelID: ClientFixtures.model.id,
            count: 1, settings: ClientFixtures.settings))
        do {
            _ = try await bed.client.offer(job)
            Issue.record("A cached capability authorized a command")
        } catch let error as LinkError { #expect(error.code == .unsupported) }
        #expect(bed.host.commands.isEmpty)
        try await LinkGapRecoveryTests.settle { bed.host.isAuthenticated }
        world.multiHost = false
        try await bed.host.announce(world, kind: .snapshot)
        try await LinkGapRecoveryTests.settle { bed.client.hasFreshSnapshot }
        #expect(bed.client.authenticatedSessionID != nil)
        #expect(!bed.client.supportsMultiHost, "a downgraded Mac keeps its old wire contract")
        world.multiHost = true
        try await bed.host.announce(world, kind: .snapshot)
        try await LinkGapRecoveryTests.settle { bed.client.supportsMultiHost }
        #expect(bed.client.supportsMultiHost)
    }
}
