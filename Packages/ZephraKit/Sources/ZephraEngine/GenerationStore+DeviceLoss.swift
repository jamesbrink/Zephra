import ZephraCore

/// What the store does once the GPU has stopped running this process's work: nothing more.
///
/// A fault is one run (`BackendError.deviceFailed`, Try Again works). This is the other kind,
/// measured on a 16 GB mini on 2026-09-15: after two driver resets the process's command
/// buffers came back `kIOGPUCommandBufferCallbackErrorSubmissionsIgnored` in a third of a
/// second, and they went on doing so for four minutes — through every Try Again, through an
/// unload and a reload, and through a switch to another model — until the app was quit. MLX
/// leaks its `MTLDevice` as a process-wide singleton with no way to rebuild it, so there is no
/// in-process remedy to reach for.
///
/// Two rules follow, and they are the whole of this file. The store refuses everything
/// (`acceptsWork`), so no door hands the actor work that cannot run; and it stops *undoing*
/// things too, because releasing the weights, releasing the allocator's cache and synchronizing
/// Metal are each one more command buffer submitted into a channel the driver is refusing.
/// The app relaunches instead, which is the one thing that has been shown to work.
extension GenerationStore {
    /// Notices a device loss the runtime latched outside any run — the allocator's cache handed
    /// back by an unload is where bender's first ignored submission landed — and answers
    /// whether this call is the one that noticed. `transition(to:)` asks on every state change.
    @discardableResult
    func noteDeviceLossIfLatched() -> Bool {
        guard !deviceLost, runtime?.isDeviceLost == true else { return false }
        closeForDeviceLoss(BackendError.deviceLostSentence)
        return true
    }

    /// Whether `error` is the end of the GPU for this launch, latching it where it is.
    ///
    /// The three places a backend call can throw ask this: the run, the load and the upscale.
    /// It is the throw rather than the runtime's latch that matters for a store under test,
    /// which has no runtime to ask.
    @discardableResult
    func noteIfDeviceLost(_ error: any Error) -> Bool {
        guard let backend = error as? BackendError, case .deviceLost(let text) = backend else {
            return noteDeviceLossIfLatched()
        }
        guard !deviceLost else { return true }
        closeForDeviceLoss(text)
        return true
    }

    /// Closes admission and says so once, at error, with the runtime's own text and the one
    /// remedy. The `make logs` line before it names the first fault of the process, which is
    /// what says why the driver stopped listening.
    private func closeForDeviceLoss(_ text: String) {
        deviceLost = true
        idleTask?.cancel()
        idleTask = nil
        queue.removeAll()
        dropChains()
        running = nil
        clearLivePreview()
        logger.error(
            """
            the GPU is lost for this launch: \(text, privacy: .public) \
            — no more work is submitted and Zephra relaunches to get it back
            """)
    }
}
