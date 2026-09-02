import Testing
import ZephraCore

@Suite("BackendRegistry")
struct BackendRegistryTests {
    @Test("a registered family is built by its own factory")
    func makesTheRegisteredBackend() throws {
        let registry = BackendRegistry().registering(.zImage) { descriptor in
            StubBackend(loadedModelID: descriptor.id)
        }
        #expect(registry.handles(.zImage))
        let backend = try registry.make(ModelCatalog.default)
        #expect(backend.loadedModelID == ModelCatalog.default.id)
    }

    @Test("an unregistered family throws rather than falling back to whatever is there")
    func unknownFamilyThrows() throws {
        let registry = BackendRegistry().registering("something-else") { _ in StubBackend() }
        #expect(registry.handles(.zImage) == false)
        #expect(throws: BackendRegistryError.noBackend(.zImage)) {
            _ = try registry.make(ModelCatalog.default)
        }
    }

    @Test("registering the same family twice keeps the later factory")
    func laterRegistrationWins() throws {
        var registry = BackendRegistry()
        registry.register(.zImage) { _ in StubBackend(loadedModelID: "first") }
        registry.register(.zImage) { _ in StubBackend(loadedModelID: "second") }
        #expect(try registry.make(ModelCatalog.default).loadedModelID == "second")
    }
}
