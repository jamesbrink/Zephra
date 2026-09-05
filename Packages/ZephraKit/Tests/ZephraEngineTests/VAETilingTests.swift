import Foundation
import Testing
import ZephraCore

@testable import ZephraEngine

@MainActor
@Suite("The decode is tiled for the model that runs")
struct VAETilingTests {
    /// A 16 GB Mac: the 8-bit Z-Image (23.5 GB peak) tiles under Automatic, klein 4-bit
    /// (12.1 GB peak) does not.
    static let sixteen = MemoryBudget(physicalMemory: 16 << 30, gpuWorkingSet: 16_000_000_000)
    static let klein = ModelCatalog.descriptor(id: "flux2-klein-4b-4bit")!

    @Test("a model chosen mid-run does not change the running run's tile")
    func switchMidRunKeepsTheRunningTile() async throws {
        let bed = EngineTestBed()
        let store = bed.store()
        store.warmsUpAfterLoad = false
        store.vaeTilingPolicy = VAETilingPolicy(mode: .automatic, budget: Self.sixteen)
        await store.bootstrap()
        bed.control.update { $0.stepDelay = .milliseconds(10) }
        store.settings.prompt = "x"
        store.settings.steps = 4
        store.generate()
        try await bed.waitForStep()

        store.switchModel(to: Self.klein)
        #expect(store.descriptor.id == Self.klein.id, "the choice lands at once")
        while store.isDraining || store.isSwappingModel { await store.settle() }
        await store.settle()
        #expect(bed.control.settings.tileAtGenerate == VAETilingPolicy.latentTileEdge,
                "the running run decoded at its own model's tile")
        #expect(store.history.count == 1)
        #expect(store.loadedDescriptor?.id == Self.klein.id)

        store.generate()
        while store.isDraining { await store.settle() }
        await store.settle()
        #expect(bed.control.settings.tileAtGenerate == nil, "klein fits, so it decodes whole")
        await store.shutdown()
    }

    @Test("changing the tiling preference reaches the next run without a reload")
    func preferenceReachesTheNextRun() async throws {
        let bed = EngineTestBed()
        bed.control.update { $0.stepDelay = .zero }
        let store = bed.store()
        store.warmsUpAfterLoad = false
        store.vaeTilingPolicy = VAETilingPolicy(mode: .always, budget: Self.sixteen)
        await store.bootstrap()
        let loads = bed.control.settings.loads
        store.settings.prompt = "x"
        store.generate()
        await store.settle()
        #expect(bed.control.settings.tileAtGenerate == VAETilingPolicy.latentTileEdge)

        store.setVAETilingPolicy(VAETilingPolicy(mode: .never, budget: Self.sixteen))
        store.generate()
        await store.settle()
        #expect(bed.control.settings.tileAtGenerate == nil)
        #expect(bed.control.settings.loads == loads, "a tile is a variable of the decode, not the load")
        await store.shutdown()
    }

    @Test("warm-up decodes at the loaded model's tile")
    func warmUpUsesTheTile() async throws {
        let bed = EngineTestBed()
        bed.control.update { $0.stepDelay = .zero }
        let store = bed.store()
        store.warmsUpAfterLoad = true
        store.vaeTilingPolicy = VAETilingPolicy(mode: .automatic, budget: Self.sixteen)
        await store.bootstrap()
        #expect(store.state == .ready)
        #expect(bed.control.settings.generations == 1, "the warm-up ran")
        #expect(bed.control.settings.tileAtGenerate == VAETilingPolicy.latentTileEdge)
        await store.shutdown()
    }
}
