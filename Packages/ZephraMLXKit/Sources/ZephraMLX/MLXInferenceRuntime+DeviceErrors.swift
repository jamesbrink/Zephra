import ZephraCore

/// Turning a GPU fault into a failed run instead of a dead process.
///
/// MLX raises an error on the thread that asked for the work and, with no handler installed,
/// ends the process there. Every backend call runs on `InferenceActor`'s serial queue inside a
/// live task, so the handler is reached on that queue and can cancel that task.
///
/// Nothing is handed to MLX here. Its scoped handlers take a closure, and passing this body to
/// one would send the run off the actor's queue — the compiler says so — so the boundary is a
/// box in `DeviceFaultSink` and the handler `MLXRuntime.installErrorLogging` puts in place.
extension MLXInferenceRuntime {
    public nonisolated(nonsending) func catchingDeviceErrors<R>(_ body: nonisolated(nonsending) () async throws -> R)
        async throws -> R
    {
        // Self-sufficient: the boundary is only a box until the handler that fills it is in,
        // and a build that forgot to install it at launch would have no boundary at all. Once
        // per process, whoever asks first.
        MLXRuntime.installErrorLogging()
        let box = DeviceErrorBox()
        let earlier = DeviceFaultSink.arm(box)
        defer { DeviceFaultSink.disarm(restoring: earlier) }
        do {
            let value = try await body()
            // A fault MLX reported that nothing in the body happened to notice still cost the
            // run: the value handed back was computed over the failed command buffer.
            if let message = box.firstMessage { throw BackendError.deviceFailed(message) }
            return value
        } catch {
            // The fault wins over the cancellation it caused, or a lost picture would be
            // reported as a Stop nobody pressed.
            if let message = box.firstMessage { throw BackendError.deviceFailed(message) }
            throw error
        }
    }

    public func installDeviceErrorLogging() {
        MLXRuntime.installErrorLogging()
    }
}
