import Foundation
import Testing
import ZephraCore
import ZephraLinkClient
import ZephraLinkProtocol
@testable import ZephraMobile

@MainActor @Suite("Reference resolution cannot dispatch an older picture by accident")
struct ReferenceResolutionTests {
    @Test func offlineSourceAndDuplicateNames() async throws {
        let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let catalog = LibraryCatalog(libraryRoot: nil, filesRoot: directory)
        let ids = (0..<2).map { _ in HostID(keys: DeviceIdentity().publicKeys) }
        var entries: [CachedEntry] = []
        for (index, id) in ids.enumerated() {
            let child = catalog.addHost(id, client: MobilePreview.unpairedClient(), frozen: true)
            await child.stopAndDrain()
            let entry = CachedEntry(LibraryFixtures.cached("same.png").entry, hostID: id)
            child.publish([entry]); entries.append(entry)
            let data = ReferenceIntentTests.Bed.picture(width: index == 0 ? 64 : 32, height: index == 0 ? 32 : 64)
            await catalog.fileStore.store(data, as: catalog.mediaKey(entry, fallback: entry.fileName))
        }
        let intent = ReferenceIntent(), draft = PromptDraft()
        let seed = draft.settings.seed
        intent.use(entries[0].id)
        #expect(!intent.canGenerate)
        await ReferenceAdoption.take(intent, from: catalog) { picture, origin in
            draft.adopt(picture, origin: origin, fitting: ReferenceIntentTests.Bed.pictureCapabilities.capabilities)
            return true
        }
        #expect(intent.canGenerate)
        #expect(draft.referenceSize == ImageSize(width: 64, height: 32))
        #expect(draft.referenceOrigin == entries[0].id)
        #expect(draft.settings.seed == seed)
        let bytes = try #require(draft.reference)
        let input = GenerationInput(data: bytes,
            originHost: catalog.entry(named: try #require(draft.referenceOrigin))?.hostID,
            dimensions: draft.referenceSize)
        #expect(input.originHost == ids[0])
        #expect(input.matches(bytes))
        // B's same filename is not a fallback for an unavailable source from A.
        await catalog.fileStore.remove(prefix: ids[0].rawValue + "-")
        intent.use(entries[0].id)
        await ReferenceAdoption.take(intent, from: catalog) { _, _ in Issue.record("An unavailable source was substituted"); return false }
        #expect(!intent.canGenerate)
        #expect(intent.note != nil)
        #expect(draft.reference == bytes)
        intent.clear()
        #expect(intent.canGenerate)
        for id in ids { await catalog.removeHost(id) }
    }
    @Test("An old photo task cannot start a new selection after Clear")
    func delayedTaskStartup() async {
        let intent = ReferenceIntent()
        intent.beginSelection()
        let revision = intent.revision
        let (gate, release) = AsyncStream<Void>.makeStream()
        var loaded = false
        let task = Task {
            for await _ in gate {}
            await ReferenceAdoption.resolve(intent, revision: revision, load: {
                loaded = true
                return Data()
            }, fill: { _ in Issue.record("A cleared photo was adopted"); return true })
        }
        intent.clear()
        release.finish()
        await task.value
        #expect(!loaded)
        #expect(intent.canGenerate)
    }
    @Test func supersededAndClearedSelections() {
        let intent = ReferenceIntent()
        intent.use("first")
        let first = intent.revision
        intent.use("second")
        intent.resolved(first, success: true)
        #expect(!intent.canGenerate && intent.isResolving)
        #expect(intent.fileName == "second")
        let second = intent.revision
        intent.clear()
        intent.resolved(second, success: false)
        #expect(intent.canGenerate)
        #expect(intent.note == nil)
    }
}
