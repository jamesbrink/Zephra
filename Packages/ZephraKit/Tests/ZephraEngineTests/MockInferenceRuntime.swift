import ZephraCore

/// A runtime with no GPU behind it: every knob is a no-op except the VAE tile, which it
/// records on the shared dial so a test can see what the actor set before a run.
struct MockInferenceRuntime: InferenceRuntime {
    let control: MockBackendControl

    func synchronize() {}
    func setCacheLimit(bytes: Int) {}
    func setMemoryLimit(bytes: Int) {}
    func deviceSummary() -> String { "mock" }
    func memorySnapshot() -> MemorySnapshot { control.settings.memory }

    func setVAETileSize(_ tile: Int?) {
        control.update { $0.vaeTile = tile }
    }

    func vaeTileSize() -> Int? { control.settings.vaeTile }

    func releaseCache() {
        control.update { $0.cacheReleases += 1 }
    }

    /// `MLXInferenceRuntime`'s boundary over the dial instead of over MLX: the fault the mock
    /// left behind wins on both ways out, so the cancellation it caused never reads as a stop.
    nonisolated(nonsending) func catchingDeviceErrors<R>(_ body: () async throws -> R)
        async throws -> R
    {
        do {
            let value = try await body()
            if let message = control.settings.deviceErrorRaised {
                throw BackendError.deviceFailed(message)
            }
            return value
        } catch {
            if let message = control.settings.deviceErrorRaised {
                throw BackendError.deviceFailed(message)
            }
            throw error
        }
    }
}
