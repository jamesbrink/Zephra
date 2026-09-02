import ZephraCore

/// The one symbol a composition root needs in order to wire Qwen-Image into the engine.
public nonisolated enum QwenImageBackendFactory {
    /// Makes a fresh, idle `QwenImageBackend`.
    public static let make: BackendFactory = { _ in QwenImageBackend() }
}
