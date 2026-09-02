/// What can go wrong when a descriptor is handed to a registry that cannot run it.
public enum BackendRegistryError: Error, Sendable, Hashable {
    /// No factory was registered for the model's backend identifier.
    case noBackend(BackendID)
}
