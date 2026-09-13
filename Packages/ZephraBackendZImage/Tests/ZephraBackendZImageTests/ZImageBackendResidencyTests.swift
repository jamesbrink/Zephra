import Testing
import ZephraCore

@testable import ZephraBackendZImage

/// Nothing here loads weights, so what can be pinned without a snapshot is the idle answer:
/// this family used to say `.resident` the moment anything was loaded, because it could not
/// stream. It can now, so the answer is what `load` was given, and nothing when nothing is.
@Suite("What a Z-Image backend says its weights are")
struct ZImageBackendResidencyTests {
    @Test("an idle backend holds no weights and no residency")
    func idleBackendHasNoResidency() {
        let backend = ZImageBackend()
        #expect(backend.loadedModelID == nil)
        #expect(backend.loadedResidency == nil)
    }

    @Test("unloading a backend that never loaded leaves it idle")
    func unloadingIdleIsIdle() {
        let backend = ZImageBackend()
        backend.unload()
        #expect(backend.loadedResidency == nil)
    }
}
