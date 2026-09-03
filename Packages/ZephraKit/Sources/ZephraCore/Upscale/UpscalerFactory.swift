/// Makes an upscaler. A factory rather than an instance for the reason `BackendFactory` is
/// one: upscalers are not Sendable, so the engine builds the one it owns inside its own
/// executor's isolation, and what crosses the boundary is this closure.
public typealias UpscalerFactory = @Sendable () -> any ImageUpscaler
