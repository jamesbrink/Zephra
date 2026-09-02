import Foundation
import Testing
import ZephraCore

@testable import ZephraEngine

@MainActor
@Suite("GenerationStore availability")
struct ModelAvailabilityTests {
    @Test("bootstrap fills the availability map for every model in the catalog")
    func bootstrapFillsTheMap() async throws {
        let bed = EngineTestBed()
        let store = bed.store()
        store.warmsUpAfterLoad = false
        #expect(store.availability.isEmpty)

        await store.bootstrap()

        for model in ModelCatalog.all {
            #expect(store.availability[model.id] == .available)
        }
    }

    @Test("a model whose family no engine answers for reads as missing, not as a crash")
    func aFamilyWithNoBackendIsMissing() async throws {
        let bed = EngineTestBed()
        // Only Z-Image is registered, so every other family in the catalog is unanswerable.
        let store = GenerationStore(
            descriptor: ModelCatalog.default,
            registry: bed.registry([.zImage]),
            outputDirectory: bed.directory
        )
        store.warmsUpAfterLoad = false
        await store.bootstrap()

        for model in ModelCatalog.all where model.backend != .zImage {
            guard case .missing(let reason) = store.availability[model.id] else {
                Issue.record("\(model.id) has no engine here, so it cannot read as available")
                continue
            }
            #expect(reason.contains(model.backend.rawValue))
        }
    }

    @Test("a refresh picks up an answer that changed, without loading anything")
    func refreshPicksUpChanges() async throws {
        let bed = EngineTestBed()
        let id = ModelCatalog.default.id
        bed.control.update { $0.availability[id] = .needsDownload(bytes: 13_280_000_000) }
        let store = bed.store()
        await store.refreshAvailability()
        #expect(store.availability[id] == .needsDownload(bytes: 13_280_000_000))
        #expect(bed.control.settings.loads == 0, "asking must never load anything")

        bed.control.update { $0.availability[id] = .available }
        await store.refreshAvailability()
        #expect(store.availability[id] == .available)
    }

    @Test("switching to another model refreshes what is known about the catalog")
    func switchRefreshesTheMap() async throws {
        let bed = EngineTestBed()
        let store = bed.store()
        store.warmsUpAfterLoad = false
        await store.bootstrap()

        bed.control.update { $0.availability[ModelCatalog.default.id] = .missing(reason: "gone") }
        store.switchModel(to: ModelSwitchingTests.smaller)
        await store.settle()

        #expect(store.availability[ModelCatalog.default.id] == .missing(reason: "gone"))
    }

    @Test("a preview store has no backend, so nothing is ever asked")
    func previewStoreAsksNothing() async throws {
        let store = GenerationStore.preview(state: .ready)
        await store.refreshAvailability()
        #expect(store.availability[ModelCatalog.default.id] == .available)
    }
}
