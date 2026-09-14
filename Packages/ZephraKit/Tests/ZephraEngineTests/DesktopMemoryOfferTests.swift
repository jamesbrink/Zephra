import Testing
import ZephraCore
import ZephraLinkProtocol
@testable import ZephraEngine

@MainActor
@Suite("Desktop memory policy crosses the authenticated offer wire")
struct DesktopMemoryOfferTests {
    @Test func streamedOfferUsesDesktopPolicy() async throws {
        try await check(ModelCatalog.zImageTurbo8bit, streaming: .always, tiling: .never)
    }

    @Test func tiledOfferUsesDesktopPolicy() async throws {
        try await check(ModelCatalog.flux2Klein4bit, streaming: .never, tiling: .always)
    }

    @Test func loadedResidencyWinsOverDeferredPreference() async throws {
        let bed = CompanionTestBed()
        await bed.bootstrap()
        let phone = try await bed.pairedPhone()
        _ = try await phone.snapshot()
        let model = ModelCatalog.zImageTurbo8bit
        bed.store.memoryBudget = MemoryGuardStoreTests.straddling
        bed.store.loadedDescriptor = model
        bed.store.loadedResidency = .streamed
        bed.store.weightResidencyPolicy = WeightResidencyPolicy(mode: .never, budget: bed.store.memoryBudget)
        bed.store.availability[model.id] = .available
        var settings = model.capabilities.clamp(GenerationSettings.defaults(for: model))
        settings.prompt = "the loaded weights remain streamed"
        let job = StrictGeneration(request: GenerationRequest(modelID: model.id, count: 1, settings: settings))
        guard case .multiHost(.offer(let offer)) = try await phone.request(.multiHost(.offer(job))) else {
            Issue.record("Missing offer"); await bed.shutdown(); return
        }
        #expect(offer.refusal == nil)
        #expect(offer.memoryMargin > 0)
        #expect(offer.modelLoaded)
        await bed.shutdown()
    }

    private func check(_ model: ModelDescriptor, streaming: WeightResidencyMode,
                       tiling: VAETilingMode) async throws {
        let bed = CompanionTestBed()
        await bed.bootstrap()
        let phone = try await bed.pairedPhone()
        _ = try await phone.snapshot()
        bed.store.memoryBudget = MemoryGuardStoreTests.straddling
        bed.store.loadedDescriptor = nil
        bed.store.loadedResidency = nil
        bed.store.weightResidencyPolicy = WeightResidencyPolicy(mode: streaming, budget: bed.store.memoryBudget)
        bed.store.setVAETilingPolicy(VAETilingPolicy(mode: tiling, budget: bed.store.memoryBudget))
        bed.store.availability[model.id] = .available
        var settings = model.capabilities.clamp(GenerationSettings.defaults(for: model))
        settings.prompt = "an offer without a render"
        let job = StrictGeneration(request: GenerationRequest(modelID: model.id, count: 1, settings: settings))
        guard case .multiHost(.offer(let accepted)) = try await phone.request(.multiHost(.offer(job))) else {
            Issue.record("Missing offer"); await bed.shutdown(); return
        }
        #expect(accepted.refusal == nil)
        #expect(accepted.memoryMargin > 0)
        #expect(Double(model.peakBytes) > bed.store.memoryBudget.bytes)
        bed.store.memoryBudget = MemoryBudget(physicalMemory: 1 << 30, gpuWorkingSet: 1 << 29)
        guard case .multiHost(.offer(let refused)) = try await phone.request(.multiHost(.offer(job))) else {
            Issue.record("Missing refusal"); await bed.shutdown(); return
        }
        #expect(refused.refusal == bed.store.strictRefusal(for: model, settings: settings, count: 1))
        #expect(refused.refusal != nil)
        #expect(refused.memoryMargin < 0)
        #expect(bed.store.running == nil)
        #expect(bed.store.queue.isEmpty)
        await bed.shutdown()
    }
}
