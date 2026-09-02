import ZephraBackendQwenImage
import ZephraBackendZImage
import ZephraCore

/// The tool's composition root: the one place ZephraBench names a concrete backend.
///
/// It mirrors `ZephraApp.makeStore` deliberately. A benchmark that built one backend by hand
/// would measure a construction path the app never takes, and it could not measure a second
/// model family at all — the descriptor decides which engine runs, exactly as it does in the app.
enum BenchBackends {
    /// Every backend this build can measure.
    static func registry() -> BackendRegistry {
        var registry = BackendRegistry()
        registry.register(.zImage, ZImageBackendFactory.make)
        registry.register(.qwenImage, QwenImageBackendFactory.make)
        return registry
    }
}
