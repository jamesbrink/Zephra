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
    @Test("A relay gap may expire one offer without preventing the next refresh")
    func gapOutlastsOffer() async throws {
        let bed = LinkClientUnderTest(remembering: DeviceIdentity())
        defer { Task { await bed.client.disconnect(); await bed.host.stop() } }
        bed.client.frameHold = .milliseconds(150)
        await bed.client.connect()
        try await LinkGapRecoveryTests.settle { bed.host.isAuthenticated }
        var snapshot = ClientFixtures.snapshot
        snapshot.multiHost = true
        bed.host.world = snapshot
        try await bed.host.announce(snapshot, kind: .snapshot)
        try await LinkGapRecoveryTests.settle { bed.client.libraryIsComplete }
        let offer = HostOffer(refusal: nil, queueSeconds: 0, preparationSeconds: 0,
            executionSeconds: 10, memoryMargin: 1, modelLoaded: true, queueCount: 0,
            queueRevision: "ready", physicalMemory: 32_000_000_000)
        bed.host.onCommand = { command in
            if case .multiHost(.offer) = command { bed.host.reply = .multiHost(.offer(offer)) }
            else { bed.host.reply = nil }
        }
        let job = StrictGeneration(request: GenerationRequest(modelID: ClientFixtures.model.id,
            count: 1, settings: ClientFixtures.settings))
        bed.road.dropFrame()
        try await bed.host.announce(LinkReorderingTests.progress(step: 1), kind: .delta)
        let expired = try? await bed.client.offer(job, timeout: .milliseconds(30))
        #expect(expired == nil)
        try await LinkGapRecoveryTests.settle { bed.host.commands.contains(.resync) }
        #expect(bed.client.connection.isLive)
        #expect(try await bed.client.offer(job) == offer)
        try await LinkGapRecoveryTests.settle { bed.client.pending.isEmpty }
        #expect(bed.client.pending.isEmpty)
    }

}
