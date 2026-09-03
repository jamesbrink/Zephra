import ZephraCore

/// The one public entry point: how the app registers this family without naming its types.
public nonisolated enum Flux2BackendFactory {
    /// Builds a fresh, idle backend. The descriptor is ignored because one backend serves every
    /// variant of the family; it arrives again at `ensureAvailable`.
    public static let make: BackendFactory = { _ in Flux2Backend() }
}
