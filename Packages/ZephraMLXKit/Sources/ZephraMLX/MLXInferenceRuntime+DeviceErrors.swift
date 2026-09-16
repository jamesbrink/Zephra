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
    /// Runs `body` with MLX's errors collected, and turns the first of them into
    /// `BackendError.deviceFailed`.
    ///
    /// The boundary is open for wall-clock time rather than for a call: MLX work that runs on
    /// `InferenceActor` between the body's own suspension points — the allocator's cache handed
    /// back by an `unload` that interleaved there, say — is charged to whatever boundary is
    /// open. That is the truthful answer, since the device faulted while this run was on it,
    /// and it costs the interleaving work nothing: only the task the boundary was armed on is
    /// ever cancelled (`DeviceFaultSink`).
    ///
    /// The boundary closes with a `synchronize`, which is what keeps one run's fault out of the
    /// next run's box: a streamed pass leaves `asyncEval` read-ahead queued past the end of the
    /// layer that asked for it, and a fault from those reads would otherwise be raised after
    /// this boundary had gone and land in the next one. It costs the wait for the reads already
    /// queued — a couple of layers' weights, not a pass — on every call.
    public nonisolated(nonsending) func catchingDeviceErrors<R>(
        _ body: nonisolated(nonsending) () async throws -> R
    ) async throws -> R {
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
            if let message = Self.settle(box) { throw Self.failure(message) }
            return value
        } catch {
            // The fault wins over the cancellation it caused, or a lost picture would be
            // reported as a Stop nobody pressed.
            if let message = Self.settle(box) { throw Self.failure(message) }
            throw error
        }
    }

    /// Which failure one fault is: a run lost, or the GPU lost.
    ///
    /// The process latch rather than this message alone, so a code 5 arriving after the driver
    /// has already stopped running this process's buffers is still reported as the end of the
    /// GPU: a victim is recoverable, and a victim over a refusing client is not.
    private static func failure(_ message: String) -> BackendError {
        DeviceFaultSink.faults.isLost
            ? .deviceLost(message)
            : .deviceFailed(message)
    }

    /// Waits for the device work this run left queued, then says what the boundary caught —
    /// both halves before the slot is given back, so a read-ahead's fault is this run's.
    private static func settle(_ box: DeviceErrorBox) -> String? {
        MLXRuntime.synchronize()
        return box.firstMessage
    }

    public func installDeviceErrorLogging() {
        MLXRuntime.installErrorLogging()
    }
}
