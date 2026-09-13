import Foundation
import Testing
@testable import ZephraLinkClient
import ZephraLinkProtocol

@MainActor
@Suite("A silent Mac cannot expire another Mac's healthy offer")
struct OfferDeadlineTests {
    @Test("A parallel offer round finishes within its short timeout and releases pending requests")
    func stalledPeer() async throws {
        let healthy = LinkClientUnderTest(), stalled = LinkClientUnderTest()
        defer { Task { await healthy.host.stop(); await stalled.host.stop() } }
        try await healthy.client.pair(with: healthy.pairingCode())
        try await stalled.client.pair(with: stalled.pairingCode())
        var snapshot = ClientFixtures.snapshot
        snapshot.multiHost = true
        for _ in 0..<8 { await Task.yield() }
        try await healthy.host.announce(snapshot, kind: .snapshot)
        try await stalled.host.announce(snapshot, kind: .snapshot)
        let deadline = ContinuousClock.now + .seconds(2)
        while !healthy.client.supportsMultiHost || !stalled.client.supportsMultiHost {
            guard ContinuousClock.now < deadline else { Issue.record("Snapshots missing"); return }
            try await Task.sleep(for: .milliseconds(5))
        }
        healthy.client.endLibraryPull(); stalled.client.endLibraryPull()
        let offer = HostOffer(refusal: nil, queueSeconds: 0, preparationSeconds: 0,
            executionSeconds: 10, memoryMargin: 1, modelLoaded: true, queueCount: 0,
            queueRevision: "ready", physicalMemory: 32_000_000_000)
        healthy.host.reply = .multiHost(.offer(offer))
        stalled.host.silentOffers = true
        let job = StrictGeneration(request: GenerationRequest(modelID: ClientFixtures.model.id,
            count: 1, settings: ClientFixtures.settings))
        let started = ContinuousClock.now
        async let a = try? healthy.client.offer(job, timeout: .milliseconds(100))
        async let b = try? stalled.client.offer(job, timeout: .milliseconds(100))
        let (good, absent) = await (a, b)
        #expect(good == offer)
        #expect(absent == nil)
        #expect(started.duration(to: .now) < .seconds(1))
        #expect(stalled.client.pending.isEmpty)
        #expect(HostSelection.best([HostCandidate(id: try #require(healthy.client.hostID), offer: try #require(good))]) != nil)
    }
}
