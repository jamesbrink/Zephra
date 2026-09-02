/// Which engine runs which family of models.
///
/// A descriptor names its backend; this maps that name to the code that can build one. It is a
/// value assembled by the composition root and handed down, rather than a static table: the app
/// registers the backends it links and a test registers a mock, without either being able to see
/// the other's. `ModelCatalog` stays the only static registry in the codebase.
public struct BackendRegistry: Sendable {
    private var factories: [BackendID: BackendFactory] = [:]

    /// Creates an empty registry, which can build nothing until something is registered.
    public init() {}

    /// Registers the factory that builds backends for `id`, replacing any earlier one.
    public mutating func register(_ id: BackendID, _ factory: @escaping BackendFactory) {
        factories[id] = factory
    }

    /// A copy with `factory` registered for `id`, for wiring a registry up in one expression.
    public func registering(
        _ id: BackendID,
        _ factory: @escaping BackendFactory
    ) -> BackendRegistry {
        var copy = self
        copy.register(id, factory)
        return copy
    }

    /// Whether a model naming this backend can be run at all in this build.
    public func handles(_ id: BackendID) -> Bool {
        factories[id] != nil
    }

    /// Builds a backend for `descriptor`, or throws `BackendRegistryError.noBackend` when this
    /// build has no implementation for the family the descriptor names.
    public func make(_ descriptor: ModelDescriptor) throws -> any ImageGenerationBackend {
        guard let factory = factories[descriptor.backend] else {
            throw BackendRegistryError.noBackend(descriptor.backend)
        }
        return factory(descriptor)
    }
}
