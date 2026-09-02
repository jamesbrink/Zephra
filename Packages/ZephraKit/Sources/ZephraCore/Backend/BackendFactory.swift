/// Makes a backend for a descriptor. It is a factory rather than an instance because backends
/// are not Sendable: the engine layer has to construct one inside its own executor's isolation,
/// so what crosses the boundary is this closure, not a live object.
public typealias BackendFactory = @Sendable (ModelDescriptor) -> any ImageGenerationBackend
