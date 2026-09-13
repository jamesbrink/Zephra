import Foundation
import Testing
import ZephraLinkProtocol
@testable import ZephraLinkClient

@MainActor @Suite("A preview never follows a different running job")
struct PreviewRunTransitionTests {
    @Test(arguments: [false, true]) func busyToBusy(_ snapshot: Bool) async throws {
        let bed = LinkClientUnderTest(remembering: DeviceIdentity())
        await bed.client.connect()
        try await LinkGapRecoveryTests.settle { bed.host.isAuthenticated }
        var world = ClientFixtures.snapshot
        world.engine = EngineStateDTO(kind: .generating, isBusy: true)
        let old = QueuedEntry(id: UUID(), batchID: UUID(), batchIndex: 0,
            modelID: ClientFixtures.model.id, settings: ClientFixtures.settings)
        world.running = old
        try await bed.host.announce(world, kind: .snapshot)
        let frame = PreviewFrameDTO(jpeg: Data([1]), width: 1, height: 1, step: 1, steps: 10)
        try await bed.host.announce(frame, kind: .preview)
        try await LinkGapRecoveryTests.settle { bed.client.preview != nil }
        var next = old; next.id = UUID()
        if snapshot {
            world.running = next
            try await bed.host.announce(world, kind: .snapshot)
        } else { try await bed.host.announce(StateDelta.running(next), kind: .delta) }
        try await LinkGapRecoveryTests.settle { bed.client.snapshot?.running?.id == next.id }
        #expect(bed.client.snapshot?.engine.isBusy == true)
        #expect(bed.client.preview == nil)
        await bed.client.disconnect(); await bed.host.stop()
    }
}
