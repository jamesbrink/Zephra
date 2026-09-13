import Foundation
import Testing
import ZephraLinkProtocol
@testable import ZephraLinkHost

@MainActor @Suite("A congested session retains only the newest pending preview")
struct PendingPreviewTests {
    @Test func latestFrameSurvivesCongestion() async throws {
        let bed = CompanionTestBed()
        let phone = try await bed.pairedPhone()
        _ = try await phone.snapshot()
        let session = try #require(bed.host.sessions.first)
        try await bed.waitUntil { session.queuedBytes == 0 }
        session.queuedBytes = 262_144
        let first = PreviewFrameDTO(jpeg: Data([1]), width: 1, height: 1, step: 1, steps: 10)
        let newest = PreviewFrameDTO(jpeg: Data([2]), width: 1, height: 1, step: 2, steps: 10)
        session.send(first); session.send(newest)
        #expect(session.pendingPreview == newest)
        #expect(try phone.previews().isEmpty)
        session.queuedBytes = 0
        session.flushPreview()
        let delivered = try await phone.waitFor { try? phone.previews().first }
        #expect(delivered == newest)
        #expect(session.pendingPreview == nil)
        session.queuedBytes = 262_144
        session.send(first)
        // Unsubscribing discards deferred previews as well as suppressing future ones.
        let next = QueuedEntry(id: UUID(), batchID: UUID(), batchIndex: 0,
            modelID: "next", settings: CompanionHostTests.request().settings)
        session.send(StateDelta.running(next))
        #expect(session.pendingPreview == nil, "A busy-to-busy run transition discards the prior frame")
        session.send(first)
        session.wantsPreviews = false
        session.queuedBytes = 0
        session.flushPreview()
        #expect(session.pendingPreview == nil)
        #expect(try phone.previews() == [newest])
        await bed.shutdown()
    }
}
