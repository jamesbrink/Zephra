import Foundation
import Synchronization
import Testing
import ZephraCore
import ZephraSnapshot

@testable import ZephraEngine

extension ConcurrentDownloadTests {
    @Test("Quit awaits the entire folder transaction and never reopens admission")
    func shutdownDuringFolderChange() async throws {
        let bed = EngineTestBed(), gate = BackendGate()
        bed.control.update { state in state.downloadGate = { _ in await gate.wait() } }
        let store = bed.store()
        store.retry()
        try await reached { await gate.entered }
        let target = ModelLocations(root: bed.directory.appending(path: "moved"))
        let moving = Task { try await store.changeModelDirectory(to: target) }
        try await reached { store.isChangingModelDirectory }
        var stopped = false
        let stopping = Task { await store.shutdown(); stopped = true }
        try await reached { store.isShuttingDown }
        #expect(!stopped)
        #expect(!store.canUpscale)
        await gate.open()
        _ = try await moving.value
        await stopping.value
        #expect(store.modelLocations == target)
        #expect(!store.isChangingModelDirectory)
        #expect(store.downloads.admissionClosed)
    }

    @Test("Quit awaits an image-library transaction and preserves both admission gates")
    func shutdownDuringImageDirectoryChange() async throws {
        let bed = EngineTestBed(), target = EngineTestBed(), gate = BackendGate()
        let store = bed.store(), index = bed.index()
        let image = LibraryAnnotationTests.image(seed: 71)
        try bed.library.write(image)
        store.saveTask = Task { await gate.wait() }
        try await reached { await gate.entered }
        let moving = Task { try await store.changeImageDirectory(to: target.directory, moving: true, index: index) }
        try await reached { store.isChangingImageDirectory }
        #expect(!store.canChangeModelDirectory)
        let chosen = store.descriptor
        store.switchModel(to: ModelSwitchingTests.otherFamily)
        #expect(store.descriptor == chosen)
        var stopped = false
        let stopping = Task { await store.shutdown(); stopped = true }
        try await reached { store.isShuttingDown }
        #expect(!stopped)
        #expect(!store.canChangeImageDirectory)
        await gate.open()
        _ = try await moving.value
        await stopping.value
        #expect(store.outputDirectory == target.directory)
        #expect(index.library.root == target.directory)
        #expect(index.items.count == 1)
        #expect(store.downloads.admissionClosed)
    }

    @Test("Quit awaits deletion and its inventory refresh before returning")
    func shutdownDuringDeletion() async throws {
        let bed = EngineTestBed()
        let store = bed.store()
        let entered = Mutex(false)
        let gate = DispatchSemaphore(value: 0)
        defer { gate.signal() }
        let inventory = ModelInventory(catalog: [], locations: store.modelLocations, remove: { _ in
            entered.withLock { $0 = true }
            gate.wait()
        })
        let item = ModelStorageItem(name: "unused", kind: .built, url: bed.directory.appending(path: "unused"),
            location: "unused", modelIDs: [], isComplete: true)
        let deleting = Task { await store.deleteModelStorage(item, inventory: inventory) }
        try await reached { entered.withLock { $0 } }
        var stopped = false
        let stopping = Task { await store.shutdown(); stopped = true }
        try await reached { store.isShuttingDown }
        #expect(!stopped)
        #expect(store.deletionInProgress)
        #expect(!store.canChangeImageDirectory)
        gate.signal()
        await deleting.value
        await stopping.value
        #expect(!store.deletionInProgress)
        #expect(store.downloads.admissionClosed)
    }
}
