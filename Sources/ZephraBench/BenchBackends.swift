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

    /// The GPU runtime the benchmark tunes and reads.
    ///
    /// One copy of MLX serves every backend, so the allocator's limits and its memory readings
    /// are the same answer whichever family is asked. Which one is asked still belongs here,
    /// because the rest of the tool is not allowed to know that any of them exist.
    static func runtime() -> any InferenceRuntime { ZImageInferenceRuntime() }

    /// Times one family's kernels at `tokens` without loading weights. Only Z-Image has one.
    static func microbench(tokens: Int) { ZImageMicrobench.run(tokens: tokens) }
}
