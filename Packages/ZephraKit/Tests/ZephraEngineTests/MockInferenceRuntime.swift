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
}
