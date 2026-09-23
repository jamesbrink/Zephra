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

    /// The process-wide latch, as a dial. True here means what it means in
    /// `MLXInferenceRuntime`: the driver has stopped running this process's command buffers and
    /// will go on doing so until the app is relaunched, whether or not any call threw.
    var isDeviceLost: Bool { control.settings.deviceLost }

    /// `MLXInferenceRuntime`'s boundary over the dial instead of over MLX: the fault the mock
    /// left behind wins on both ways out, so the cancellation it caused never reads as a stop.
    nonisolated(nonsending) func catchingDeviceErrors<R>(
        _ body: nonisolated(nonsending) () async throws -> R
    ) async throws -> R {
        do {
            let value = try await body()
            if let message = settle() { throw failure(message) }
            return value
        } catch {
            if let message = settle() { throw failure(message) }
            throw error
        }
    }

    /// `MLXInferenceRuntime.failure` over the dial: the real one reads the kind out of the
    /// driver's text, which the mock's message does not carry.
    private func failure(_ message: String) -> BackendError {
        control.settings.deviceFaultIsVictim ? .deviceVictim(message) : .deviceFailed(message)
    }

    /// Takes the fault rather than reading it, because the real boundary's box is made when it
    /// opens and dropped when it closes: no fault can reach a run through a box the boundary
    /// before it left behind. A test that had to clear the dial by hand was standing in for
    /// that, and hiding the day a box outlived its boundary.
    private func settle() -> String? {
        var message: String?
        control.update {
            message = $0.deviceErrorRaised
            $0.deviceErrorRaised = nil
        }
        return message
    }
}
