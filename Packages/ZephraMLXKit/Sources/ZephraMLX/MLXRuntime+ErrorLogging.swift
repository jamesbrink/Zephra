import Foundation
import MLX
import os

/// The one handler's log. A C-convention handler captures nothing, so this is a global rather
/// than something handed in.
private let deviceErrorLog = Logger(subsystem: "io.zephra", category: "runtime")

/// What MLX is told to do with every error it raises: hand it to the boundary that is
/// collecting, or, where there is none, say so and carry on.
///
/// `@Sendable` so that this global is not inferred onto the main actor, which a nonisolated
/// installer could then not read; a C handler captures nothing, so there is nothing for it to
/// be unsafe about.
private let recordOrLog:
    @convention(c) @Sendable (UnsafePointer<CChar>?, UnsafeMutableRawPointer?) -> Void = {
        message, _ in
        let text = message.map { String(cString: $0) } ?? "no message"
        switch DeviceFaultSink.record(text) {
        case .recorded:
            deviceErrorLog.error("MLX device error: \(text, privacy: .public)")
            // Nothing the run is still holding is worth walking: what it would read next came
            // out of the command buffer that failed. The kits look for a cancel between
            // denoising steps, between streamed blocks and between decode tiles, so the run
            // unwinds within one step rather than at the end of the ladder.
            //
            // The task this cancels is the one the boundary was armed on, which
            // `DeviceFaultSink` has already checked is the task raising the fault: cancelling
            // whatever task happens to be on the faulting thread would, for a fault raised by
            // the wired-limit reservation's own task, end that task rather than the run.
            withUnsafeCurrentTask { $0?.cancel() }
        case .recordedOffTask:
            // The run still fails: its box holds the message, and the device faulted while it
            // was on it. Only the cancel is withheld, because the task that raised this is
            // some other piece of device work and not the run's.
            deviceErrorLog.error(
                "MLX device error off the run's own task: \(text, privacy: .public)")
        case .echo:
            break
        case .unscoped:
            deviceErrorLog.error("MLX error outside any run: \(text, privacy: .public)")
        }
    }

/// Installed exactly once, whoever asks first: a global `let` is initialised under the
/// runtime's own once, so `installErrorLogging` may be called from the composition root and
/// from every boundary without the handler being replaced or the install racing itself.
private let handlerIsInstalled: Bool = {
    setErrorHandler(recordOrLog)
    return true
}()

extension MLXRuntime {
    /// Puts MLX's one error handler in place, in place of its default, which is to end the
    /// process.
    ///
    /// It does two jobs, because MLX offers one handler that outlives a task: it fills the box
    /// `MLXInferenceRuntime.catchingDeviceErrors` is holding, and where no boundary is holding
    /// one it writes a line to the log instead. The unscoped corners are real and none of them
    /// is worth the app: the wired-limit reservation runs on a task of its own, the allocator's
    /// cache is handed back as a model unloads, and the device is asked what generation it is
    /// before any model is loaded. Each is asked again the next time it is wanted, so a fault
    /// swallowed there is a stale reading rather than a wrong one.
    ///
    /// `MLX.setErrorHandler` is deprecated upstream in favour of its scoped handlers, and the
    /// call below warns accordingly. Those take a closure, and handing one the work would send
    /// it off `InferenceActor`'s serial queue, so this is the only handler Zephra can use: the
    /// deprecation is noted rather than worked around.
    ///
    /// Called from the composition root before the first call into MLX, and by every boundary,
    /// which is what keeps a build that forgot the first from having no boundary at all.
    public static func installErrorLogging() {
        _ = handlerIsInstalled
    }
}
