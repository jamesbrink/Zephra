import Foundation
import Testing
import ZephraCore

@testable import ZephraEngine
@testable import ZephraSnapshot

@MainActor
@Suite("Retry on a model that is already resident")
struct RetryResidentModelTests {
    @Test("retry after a generation failure keeps the weights, borrows nothing, and lets the old model's storage go after a switch")
    func retryDoesNotReloadOrLeak() async throws {
        let bed = EngineTestBed()
        let store = bed.store()
        store.warmsUpAfterLoad = false
        await store.bootstrap()
        #expect(store.state == .ready)
        let loadsBefore = bed.control.settings.loads
        let claim = try #require(bed.control.settings.lastAcquisitionID)

        bed.control.update { $0.generateError = .generationFailed("boom") }
        store.settings.prompt = "x"
        store.generate()
        await store.settle()
        #expect(store.state == .failed(.backend(.generationFailed("boom"))))
        #expect(store.loadedDescriptor != nil, "the model stays resident after a generation failure")

        bed.control.update { $0.generateError = nil }
        store.retry()
        await store.settle()
        #expect(store.state == .ready)
        #expect(bed.control.settings.loads == loadsBefore, "retry reloaded a resident model")
        #expect(store.downloads.retained[claim]?.borrowers == 1, "one borrow per resident model")

        // A generation works again without anything having been reloaded.
        store.generate()
        await store.settle()
        #expect(store.history.count == 1)

        // Switching away releases the one claim, so the old model's storage is deletable.
        store.switchModel(to: ModelSwitchingTests.otherFamily)
        await store.settle()
        #expect(store.loadedDescriptor?.id == ModelSwitchingTests.otherFamily.id)
        #expect(await store.downloads.transfers.claims[claim] == nil)
        #expect(!store.downloads.isRetained(claim))
        #expect(!store.downloads.protectedModelIDs.contains(ModelCatalog.default.id))
        let item = ModelStorageItem(
            name: "z", kind: .download, url: bed.directory.appending(path: "models/Downloads/x"),
            location: "x", modelIDs: [ModelCatalog.default.id], isComplete: true)
        #expect(!store.modelStorageIsInUse(item), "the old model's storage still counted as in use")
        await store.shutdown()
    }

    @Test("a residency change on the loaded model reloads it once and holds one lease")
    func residencyChangeReloadsOnce() async throws {
        let bed = EngineTestBed()
        let store = bed.store(descriptor: WeightResidencyStoreTests.streamable)
        store.warmsUpAfterLoad = false
        store.weightResidencyPolicy = WeightResidencyPolicy(
            mode: .never, budget: WeightResidencyStoreTests.small)
        await store.bootstrap()
        #expect(bed.control.settings.loads == 1)

        store.setWeightResidencyPolicy(
            WeightResidencyPolicy(mode: .always, budget: WeightResidencyStoreTests.roomy))
        try await bed.waitFor(store, toReach: .ready)
        await store.settle()
        #expect(bed.control.settings.loads == 2)
        #expect(store.loadedResidency == .streamed)
        let claim = try #require(bed.control.settings.lastAcquisitionID)
        #expect(await bed.holdsClaim(store))
        #expect(await bed.claimCount(store) == 1)
        #expect(store.downloads.retained[claim]?.borrowers == 1)

        store.switchModel(to: ModelSwitchingTests.otherFamily)
        await store.settle()
        #expect(await store.downloads.transfers.claims[claim] == nil)
        #expect(await bed.claimCount(store) == 1, "only the new model's claim remains")
        await store.shutdown()
    }
}
