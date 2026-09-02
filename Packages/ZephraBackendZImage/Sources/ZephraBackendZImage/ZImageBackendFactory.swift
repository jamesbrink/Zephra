import ZephraCore

/// The one symbol a composition root needs in order to wire Z-Image into the engine.
///
/// The engine takes a factory rather than a backend because backends are not Sendable, so the
/// engine has to build one inside its own isolation. The descriptor is ignored: every model
/// this backend serves runs through the same pipeline, and the descriptor arrives again at
/// `ensureAvailable`.
public nonisolated enum ZImageBackendFactory {
    /// Makes a fresh, idle `ZImageBackend`.
    public static let make: BackendFactory = { _ in ZImageBackend() }
}
