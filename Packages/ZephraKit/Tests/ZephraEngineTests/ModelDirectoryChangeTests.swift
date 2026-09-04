import Foundation
import Testing
import ZephraCore
import ZephraSnapshot

@testable import ZephraEngine

@Suite("Changing model folders stops old writes")
@MainActor
struct ModelDirectoryChangeTests {
    @Test("a change cancels an active download and retry uses only the new folder")
    func downloadIsStoppedBeforeChangingFolder() async throws {
        let bed = EngineTestBed()
        bed.control.update { $0.downloadDelay = .seconds(60) }
        let old = ModelLocations(root: bed.directory.appending(path: "old"))
        let store = bed.store(locations: old)
        store.retry()
        for _ in 0..<500 where bed.control.settings.lastLocations == nil {
            try await Task.sleep(for: .milliseconds(2))
        }
        #expect(bed.control.settings.lastLocations == old)
        let new = ModelLocations(root: bed.directory.appending(path: "new"), previous: [old.root])
        _ = try await store.changeModelDirectory(to: new)
        #expect(store.state == .idle)
        #expect(bed.control.settings.loads == 0)
        #expect(store.modelLocations == new)
        bed.control.update { $0.downloadDelay = .zero }
        store.retry()
        await store.settle()
        #expect(bed.control.settings.lastLocations == new)
        #expect(store.state == .ready)
    }

    @Test("an outstanding model switch cannot restart the old preparation")
    func pendingSwitchIsStopped() async throws {
        let bed = EngineTestBed()
        bed.control.update { $0.downloadDelay = .seconds(60) }
        let store = bed.store()
        store.retry()
        store.switchModel(to: ModelCatalog.flux2Klein4bit)
        let chosen = ModelLocations(root: bed.directory.appending(path: "new"))
        _ = try await store.changeModelDirectory(to: chosen)
        await store.settle()
        #expect(store.state == .idle)
        #expect(!store.isSwappingModel)
        #expect(store.loadedDirectory == nil)
        bed.control.update { $0.downloadDelay = .zero }
        store.retry()
        await store.settle()
        #expect(bed.control.settings.lastLocations == chosen)
    }

    @Test("all work entry points respect a folder operation already in progress")
    func operationGate() async throws {
        let bed = EngineTestBed()
        let store = bed.store()
        await store.bootstrap()
        store.modelDirectoryProgress = "Moving models"
        let model = store.descriptor
        store.switchModel(to: ModelCatalog.flux2Klein4bit)
        store.generate()
        store.queueVariation(of: LibraryFilteringTests.item(prompt: "A lighthouse", seed: 42))
        store.retry()
        #expect(store.descriptor == model)
        #expect(store.queue.isEmpty)
        #expect(!store.canGenerate && !store.canQueue && !store.canUpscale)
        await #expect(throws: ModelDirectoryError.self) {
            try await store.changeModelDirectory(to: ModelLocations(root: bed.directory))
        }
        store.modelDirectoryProgress = nil
    }

    @Test("generation and queued work refuse a folder change without discarding the queue")
    func busyGenerationIsPreserved() async throws {
        let bed = EngineTestBed()
        bed.control.update { $0.stepDelay = .seconds(60) }
        let store = bed.store()
        store.warmsUpAfterLoad = false
        await store.bootstrap()
        store.settings.prompt = "A tree"
        store.generate(count: 2)
        let queued = store.queue
        await #expect(throws: ModelDirectoryError.self) {
            try await store.changeModelDirectory(to: ModelLocations(root: bed.directory))
        }
        #expect(store.queue == queued)
        store.cancel()
        await store.settle()
    }

    @Test("migration failure retains the old destination and releases the operation gate")
    func failedMigrationKeepsLocation() async throws {
        let bed = EngineTestBed()
        let old = ModelLocations(root: bed.directory.appending(path: "old"))
        let store = bed.store(locations: old)
        await #expect(throws: ModelDirectoryError.self) {
            try await store.changeModelDirectory(to: old, moving: old.root)
        }
        #expect(store.modelLocations == old)
        #expect(!store.isChangingModelDirectory)
    }
}
