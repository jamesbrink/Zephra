import Foundation
import Testing
import ZephraCore

@testable import ZephraEngine

@Suite("The folder models are kept in reaches the backend")
@MainActor
struct ModelFolderTests {
    @Test("the folder the store was built with is the one the backend is asked to use")
    func theStoresFolderReachesTheBackend() async throws {
        let bed = EngineTestBed()
        let chosen = ModelLocations(root: bed.directory.appending(path: "Models"))
        let store = bed.store(locations: chosen)

        await store.bootstrap()
        await store.settle()
        #expect(bed.control.settings.lastLocations == chosen)
    }

    @Test("choosing another folder applies to the next load, not to what is already loaded")
    func changingTheFolderAppliesToTheNextLoad() async throws {
        let bed = EngineTestBed()
        let store = bed.store()
        await store.bootstrap()
        await store.settle()
        let first = bed.control.settings.lastLocations

        let moved = ModelLocations(root: bed.directory.appending(path: "Elsewhere"))
        #expect(await store.setModelLocations(moved))
        #expect(!(await store.setModelLocations(moved)), "the same folder twice is not a change")
        #expect(bed.control.settings.lastLocations == first, "nothing reloads on its own")

        await store.switchModel(to: ModelCatalog.flux2Klein4bit)
        await store.settle()
        #expect(bed.control.settings.lastLocations == moved)
    }
}
