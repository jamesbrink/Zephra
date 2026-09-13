import Foundation
import Testing
import ZephraLinkClient
import ZephraLinkProtocol

/// What happens to the newest frame of a run when the link goes.
///
/// It used to go with it, so a phone whose road dropped mid-run put a spinner and the word
/// "Denoising" where a picture had been — a worse account of the truth than the frame it was
/// already showing, since the Mac is very likely still making the run. Now only the Mac saying
/// the engine is not busy clears one.
@MainActor
@Suite("A preview frame outlives the road it arrived on")
struct LinkPreviewTests {
    /// A paired phone with a session already open and a frame on screen.
    private func showingAFrame() async throws -> LinkClientUnderTest {
        let bed = LinkClientUnderTest()
        try await bed.client.pair(with: bed.pairingCode())
        try await settle()
        try await bed.host.announce(Self.frame, kind: .preview)
        try await settle()
        #expect(bed.client.preview != nil)
        return bed
    }

    @Test("the road going leaves the frame where it is")
    func aDropKeepsTheFrame() async throws {
        let bed = try await showingAFrame()
        defer { Task { await bed.host.stop() } }
        bed.road.announce(.left)
        let deadline = ContinuousClock.now + .seconds(2)
        while bed.client.connection.isLive, ContinuousClock.now < deadline { try await Task.sleep(for: .milliseconds(5)) }
        #expect(!bed.client.connection.isLive)
        #expect(bed.client.preview != nil)
    }

    @Test("a snapshot saying the Mac is idle is what clears it")
    func anIdleSnapshotClearsTheFrame() async throws {
        let bed = try await showingAFrame()
        defer { Task { await bed.host.stop() } }
        try await bed.host.announce(ClientFixtures.snapshot, kind: .snapshot)
        try await settle()
        #expect(bed.client.preview == nil)
    }

    @Test("a snapshot saying the Mac is still generating leaves it alone")
    func aBusySnapshotKeepsTheFrame() async throws {
        let bed = try await showingAFrame()
        defer { Task { await bed.host.stop() } }
        var busy = ClientFixtures.snapshot
        busy.engine = EngineStateDTO(kind: .generating, step: 3, steps: 9, isBusy: true)
        try await bed.host.announce(busy, kind: .snapshot)
        try await settle()
        #expect(bed.client.preview != nil)
    }

    @Test("a delta saying the run ended clears it, as it always did")
    func anIdleDeltaClearsTheFrame() async throws {
        let bed = try await showingAFrame()
        defer { Task { await bed.host.stop() } }
        try await bed.host.announce(
            StateDelta.engine(EngineStateDTO(kind: .ready, acceptsGeneration: true)),
            kind: .delta)
        try await settle()
        #expect(bed.client.preview == nil)
    }

    /// One frame of a run, small enough to be a fixture and shaped like the real thing.
    private static let frame = PreviewFrameDTO(
        jpeg: Data([0xFF, 0xD8, 0xFF, 0xD9]), width: 2, height: 2, step: 3, steps: 9)

    /// Lets the frames in flight land: one process, one actor, a couple of turns of the loop.
    private func settle() async throws {
        for _ in 0..<8 { await Task.yield() }
    }
}
