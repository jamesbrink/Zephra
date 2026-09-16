import Foundation
import Testing
import ZephraCore

@testable import ZephraEngine
@testable import ZephraSnapshot

@MainActor
@Suite("A model's claim lives exactly as long as its weights")
struct ClaimAccountingTests {
    @Test("loading takes one claim and unloading gives it back")
    func loadingClaimsAndUnloadingReleases() async throws {
        let bed = EngineTestBed()
        let store = bed.store()
        store.warmsUpAfterLoad = false
        await store.bootstrap()
        #expect(store.state == .ready)
        let first = try #require(bed.control.settings.lastAcquisitionID)
        #expect(await bed.holdsClaim(store))
        #expect(store.downloads.retained[first] != nil)

        store.switchModel(to: ModelSwitchingTests.otherFamily)
        await store.settle()
        #expect(store.loadedDescriptor?.id == ModelSwitchingTests.otherFamily.id)
        #expect(await store.downloads.transfers.claims[first] == nil)
        #expect(store.downloads.retained[first] == nil)
        // The new model holds exactly one claim of its own.
        #expect(await bed.holdsClaim(store))
        #expect(await bed.claimCount(store) == 1)
        await store.shutdown()
    }

    @Test("unloading by hand gives the claim back, and loading again takes exactly one")
    func unloadingReleasesAndLoadingTakesOne() async throws {
        let bed = EngineTestBed()
        let store = bed.store()
        store.warmsUpAfterLoad = false
        await store.bootstrap()
        let first = try #require(bed.control.settings.lastAcquisitionID)

        store.unloadModel()
        await store.settle()
        #expect(await store.downloads.transfers.claims[first] == nil)
        #expect(store.downloads.retained[first] == nil)
        #expect(await bed.claimCount(store) == 0, "nothing is left holding a folder")

        store.loadModel()
        await store.settle()
        let second = try #require(bed.control.settings.lastAcquisitionID)
        #expect(await bed.claimCount(store) == 1)
        #expect(store.downloads.retained[second]?.borrowers == 1)
        await store.shutdown()
    }

    @Test("shutdown leaves no claim behind")
    func shutdownReleasesEverything() async throws {
        let bed = EngineTestBed()
        let store = bed.store()
        store.warmsUpAfterLoad = false
        await store.bootstrap()
        #expect(await bed.holdsClaim(store))
        await store.shutdown()
        #expect(await bed.claimCount(store) == 0)
        #expect(store.downloads.retained.isEmpty)
    }
}
