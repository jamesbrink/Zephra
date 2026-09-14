import Testing
import ZephraCore
@testable import ZephraEngine

@MainActor @Suite("Desktop offers use the execution memory configuration")
struct StrictMemoryTests {
    @Test func streamedJobUsesStreamedPeak() {
        let store = EngineTestBed().store()
        let model = ModelCatalog.zImageTurbo8bit
        store.weightResidencyPolicy = WeightResidencyPolicy(mode: .always, budget: store.memoryBudget)
        let settings = GenerationSettings.defaults(for: model)
        #expect(store.strictMemory(for: model, settings: settings) == Double(model.streamedPeakBytes))
        #expect(model.streamedPeakBytes < model.peakBytes)
    }

    @Test func tiledJobUsesTiledPeak() {
        let store = EngineTestBed().store()
        let model = ModelCatalog.flux2Klein4bit
        store.weightResidencyPolicy = WeightResidencyPolicy(mode: .never, budget: store.memoryBudget)
        store.setVAETilingPolicy(VAETilingPolicy(mode: .always, budget: store.memoryBudget))
        #expect(store.strictMemory(for: model, settings: .defaults(for: model)) == Double(model.tiledPeakBytes))
    }

    @Test func automaticStreamingFitsSmallMac() {
        let bed = EngineTestBed()
        bed.memoryBudget = MemoryGuardStoreTests.small
        let store = bed.store()
        let model = ModelCatalog.zImageTurbo8bit
        store.weightResidencyPolicy = WeightResidencyPolicy(mode: .automatic, budget: store.memoryBudget)
        #expect(store.weightResidencyPolicy.residency(for: model) == .streamed)
        #expect(store.strictMemory(for: model, settings: .defaults(for: model)) < store.memoryBudget.bytes)
        #expect(Double(model.peakBytes) > store.memoryBudget.bytes)
    }

    @Test func unloadedAutomaticOfferUsesLiveStreamingDecision() {
        let bed = EngineTestBed()
        bed.memoryBudget = MemoryBudget(physicalMemory: 16 << 30, gpuWorkingSet: 12_700_000_000)
        bed.machineMemory = MachineMemory(physicalBytes: 16 << 30, availableBytes: 11_200_000_000)
        let store = bed.store()
        let model = ModelCatalog.flux2Klein4bit
        store.weightResidencyPolicy = WeightResidencyPolicy(mode: .automatic, budget: store.memoryBudget)
        store.setVAETilingPolicy(VAETilingPolicy(mode: .never, budget: store.memoryBudget))
        var settings = GenerationSettings.defaults(for: model)
        settings.size = ImageSize(width: 1536, height: 1536)
        #expect(store.weightResidencyPolicy.residency(for: model) == .resident)
        #expect(store.loadedDescriptor == nil)
        #expect(store.strictMemory(for: model, settings: settings) == Double(model.streamedPeakBytes) * 2.25)
        #expect(store.strictMemory(for: model, settings: settings) < store.memoryBudget.bytes)
        #expect(Double(model.peakBytes) * 2.25 > store.memoryBudget.bytes)
        #expect(bed.control.settings.loads == 0)
    }

}
