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
        let store = bed.store(upscaler: bed.upscalerFactory(), families: [.zImage])
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

    @Test("a download nobody was waiting on still says so when it lands")
    func abackgroundDownloadRefreshesWhatIsKnown() async throws {
        let bed = EngineTestBed()
        let control = bed.control
        let other = ModelCatalog.zImageTurbo4bit
        control.update { $0.availability[other.id] = .needsDownload(bytes: 1) }
        let store = bed.store()
        store.warmsUpAfterLoad = false
        store.loadingMode = .onDemand
        await store.bootstrap()
        #expect(store.availability[other.id] == .needsDownload(bytes: 1))
        let loads = control.settings.loads

        // The transfer is what puts the files there, so the disk's answer moves as it runs.
        control.update { settings in
            settings.downloadGate = { model in
                guard model.id == other.id else { return }
                control.update { $0.availability[other.id] = .available }
            }
        }
        store.downloadModel(other)

        // A load refreshes availability on its way out; a download has no load behind it, so
        // without the pool saying when one lands this model reads `.needsDownload` in the menu,
        // the browser and a paired phone's summary until the next launch.
        try await bed.waitUntil { store.availability[other.id] == .available }

        #expect(control.settings.loads == loads, "a download is not a load")
        #expect(store.loadedDescriptor == nil, "and nothing was read into memory for it")
        #expect(store.descriptor.id != other.id, "nor did it become the chosen model")
        await store.shutdown()
    }

    @Test("a preview store has no backend, so nothing is ever asked")
    func previewStoreAsksNothing() async throws {
        let store = GenerationStore.preview(state: .ready)
        await store.refreshAvailability()
        #expect(store.availability[ModelCatalog.default.id] == .available)
    }
}
