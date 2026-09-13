import Testing
import ZephraCore

@testable import ZephraBackendFlux2

@Suite("An idle klein backend has loaded nothing and holds nothing")
struct Flux2BackendTests {
    @Test("a fresh backend names no model and no residency")
    func idleBackendHoldsNothing() {
        let backend = Flux2Backend()

        #expect(backend.loadedModelID == nil)
        // Nil rather than `.resident`: how the weights are held is what the last load did, and
        // a backend that has not loaded has not decided. The engine reads this to tell a
        // request for the same model the other way round from one already satisfied.
        #expect(backend.loadedResidency == nil)
    }

    @Test("this family serves FLUX.2 klein")
    func backendServesFlux2() {
        #expect(Flux2Backend.backendID == BackendID.flux2)
    }
}
