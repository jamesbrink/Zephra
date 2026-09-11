import Foundation
import Testing
import ZephraLinkClient
import ZephraLinkProtocol

/// A stream that arrives out of order, which is what the relay hands a phone during a run.
@MainActor
@Suite("A phone follows a run whose frames overtook each other")
struct LinkReorderingTests {
    @Test("two hundred deltas through a shuffling road end with the last one applied")
    func aShuffledStreamEndsInTheRightState() async throws {
        let bed = LinkClientUnderTest(remembering: DeviceIdentity())
        defer { Task { await bed.host.stop() } }
        await bed.client.connect()
        for _ in 0..<8 { await Task.yield() }
        #expect(bed.client.connection == .live(.lan))

        try await bed.host.announce(ClientFixtures.snapshot, kind: .snapshot)
        bed.road.startShuffling()
        for step in 1...200 {
            try await bed.host.announce(Self.progress(step: step), kind: .delta)
        }
        // One frame may still be held back; the flush is what releases it, and the phone's inbox
        // is what puts the pair back in the order they were sealed in.
        bed.road.stopShuffling()
        try await bed.host.announce(Self.progress(step: 200), kind: .delta)
        try await Self.settle { bed.client.snapshot?.engine.step == 200 }

        #expect(bed.road.swapCount > 0, "the road has to have actually reordered something")
        #expect(bed.client.snapshot?.engine.step == 200, "the last delta is the state that stands")
        #expect(bed.client.connection == .live(.lan), "reordering is not a reason to drop the link")
    }

    @Test("a duplicated frame changes nothing and leaves the link up")
    func aDuplicateIsHarmless() async throws {
        let bed = LinkClientUnderTest(remembering: DeviceIdentity())
        defer { Task { await bed.host.stop() } }
        await bed.client.connect()
        for _ in 0..<8 { await Task.yield() }
        try await bed.host.announce(ClientFixtures.snapshot, kind: .snapshot)
        try await bed.host.announce(Self.progress(step: 3), kind: .delta)
        try await bed.host.repeatLastFrame()
        try await bed.host.announce(Self.progress(step: 4), kind: .delta)
        try await Self.settle { bed.client.snapshot?.engine.step == 4 }

        #expect(bed.client.snapshot?.engine.step == 4)
        #expect(bed.client.connection == .live(.lan))
    }

    /// One step of a run, as the Mac publishes it.
    static func progress(step: Int) -> StateDelta {
        .engine(
            EngineStateDTO(
                kind: .generating, step: step, steps: 200, isBusy: true, acceptsGeneration: false))
    }

    /// Waits for the phone to have caught up, or gives up after a second.
    static func settle(_ until: @MainActor () -> Bool) async throws {
        for _ in 0..<100 {
            if until() { return }
            try await Task.sleep(for: .milliseconds(10))
        }
    }
}
