import ZephraBackendFlux2
import ZephraBackendQwenImage
import ZephraBackendZImage
import ZephraCore

/// The tool's composition root: the one place ZephraBench names a concrete backend.
///
/// It mirrors `ZephraApp.makeStore` deliberately. A benchmark that built one backend by hand
/// would measure a construction path the app never takes, and it could not measure a second
/// model family at all — the descriptor decides which engine runs, exactly as it does in the app.
enum BenchBackends {
    /// Every backend this build can measure, running under `environment`.
    static func registry(_ environment: InferenceEnvironment) -> BackendRegistry {
        var registry = BackendRegistry()
        registry.register(.zImage, ZImageBackendFactory.make(environment))
        registry.register(.qwenImage, QwenImageBackendFactory.make(environment))
        registry.register(.flux2, Flux2BackendFactory.make(environment))
        return registry
    }

    /// The GPU runtime the benchmark tunes and reads, for the family running `backend`.
    ///
    /// One copy of MLX serves every backend, so the allocator's limits and its memory readings
    /// are the same answer whichever family is asked; the VAE tile is not, so the handle is the
    /// running family's own. Which one still belongs here, because the rest of the tool is not
    /// allowed to know that any of them exist.
    static func runtime(for backend: BackendID) -> any InferenceRuntime {
        switch backend {
        case .qwenImage: QwenImageBackendFactory.runtime
        case .flux2: Flux2BackendFactory.runtime
        default: ZImageBackendFactory.runtime
        }
    }

    /// Times one family's kernels at `tokens` without loading weights. Only Z-Image has one.
    static func microbench(tokens: Int) { ZImageMicrobench.run(tokens: tokens) }
}
