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
}
