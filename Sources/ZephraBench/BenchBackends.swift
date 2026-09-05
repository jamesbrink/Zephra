import Foundation
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

    /// Times one family's DiT kernels at `tokens` without loading weights, or refuses when
    /// the family has no microbench: only Z-Image has one, and timing its kernels under
    /// another family's name would be a number about the wrong model.
    static func microbench(family: BackendID, tokens: Int) -> Never {
        switch family {
        case .zImage:
            ZImageMicrobench.run(tokens: tokens)
            exit(0)
        default:
            let reason =
                "ZephraBench: --micro has no kernel timings for \(family.rawValue); only Z-Image's "
                + "DiT has a microbench. Pass --model with a Z-Image entry, or run the full "
                + "benchmark for this family.\n"
            FileHandle.standardError.write(Data(reason.utf8))
            exit(2)
        }
    }
}
