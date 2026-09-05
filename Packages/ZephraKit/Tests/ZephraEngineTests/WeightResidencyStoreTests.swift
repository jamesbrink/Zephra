import Foundation
import Testing
import ZephraCore

@testable import ZephraEngine

@MainActor
@Suite("GenerationStore weight residency")
struct WeightResidencyStoreTests {
    /// A model the policy may stream: the default with a streamed figure a 16 GB Mac holds.
    static let streamable = ModelDescriptor(
        id: "streamable", displayName: "Streamable", variantName: nil, backend: .zImage,
        source: ModelCatalog.default.source, quantization: .int4, downloadBytes: 0,
        residentBytes: 21_000_000_000, peakBytes: 30_000_000_000, tiledPeakBytes: 26_000_000_000,
        streamedPeakBytes: 9_000_000_000, maxPromptTokens: 512,
        capabilities: ModelCatalog.default.capabilities, builtBytes: 0, adapters: [])

    static let small = MemoryBudget(physicalMemory: 16 << 30, gpuWorkingSet: 12_700_000_000)
    static let roomy = MemoryBudget(physicalMemory: 48 << 30, gpuWorkingSet: 38_000_000_000)

    @Test("the policy's answer is what the backend is asked for, and the store remembers it")
    func policyReachesTheBackend() async throws {
        let bed = EngineTestBed()
        let store = bed.store(descriptor: Self.streamable)
        store.warmsUpAfterLoad = false
        store.weightResidencyPolicy = WeightResidencyPolicy(mode: .automatic, budget: Self.small)
        await store.bootstrap()

        #expect(store.state == .ready)
        #expect(bed.control.settings.lastResidency == .streamed)
        #expect(store.loadedResidency == .streamed)
    }

    @Test("a policy that changes the loaded model's residency reloads it, and one that does not leaves it")
    func changingThePolicyReloads() async throws {
        let bed = EngineTestBed()
        let store = bed.store(descriptor: Self.streamable)
        store.warmsUpAfterLoad = false
        store.weightResidencyPolicy = WeightResidencyPolicy(mode: .never, budget: Self.small)
        await store.bootstrap()
        #expect(bed.control.settings.lastResidency == .resident)
        #expect(bed.control.settings.loads == 1)

        // Same answer, different budget: nothing to do.
        store.setWeightResidencyPolicy(WeightResidencyPolicy(mode: .never, budget: Self.roomy))
        #expect(store.state == .ready)
        #expect(bed.control.settings.loads == 1)

        store.setWeightResidencyPolicy(WeightResidencyPolicy(mode: .always, budget: Self.roomy))
        try await bed.waitFor(store, toReach: .ready)
        #expect(bed.control.settings.loads == 2)
        #expect(bed.control.settings.unloads >= 1)
        #expect(bed.control.settings.lastResidency == .streamed)
        #expect(store.loadedResidency == .streamed)
    }
}
