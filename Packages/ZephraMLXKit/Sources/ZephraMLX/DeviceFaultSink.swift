import Synchronization

/// Where an error MLX raises is put down, so the boundary that was running can find it.
///
/// MLX offers two ways to hear about an error: a task-local handler stack, whose type is
/// file-private upstream and reachable only by handing `withErrorHandler` a closure — which
/// would send the work off `InferenceActor`'s serial queue — and one process-wide handler.
/// Only the second is usable, so this is what stands between it and the boundary:
/// `MLXInferenceRuntime.catchingDeviceErrors` puts its box in the slot for the length of the
/// work, and the installed handler records into whatever box it finds.
///
/// One slot rather than a stack of them. It is process-wide because *MLX's handler* is, not
/// because anything here chose it, and one is enough: every piece of Metal work in the app goes
/// through the one `InferenceActor`, which runs it on a serial queue, one at a time. A nested
/// boundary would still be correct — the earlier box is handed back and put in again — and an
/// error raised by MLX work outside the actor while a boundary is open is recorded as that
/// run's, which is the truthful answer: the device faulted, and the run was on it.
enum DeviceFaultSink {
    /// What one raised error turned out to be.
    enum Reception {
        /// The first fault of a boundary that is collecting. Worth a log line and a cancel.
        case recorded
        /// A later error inside the same boundary, which the first one poisoned into being.
        case echo
        /// Raised where no boundary was collecting: the allocator's cache, the wired-limit
        /// reservation, a device query before any model is up.
        case unscoped
    }

    private static let slot = Mutex<DeviceErrorBox?>(nil)

    /// Collects into `box` from now on, and hands back the box that was armed before, for the
    /// caller to put back when it is done.
    static func arm(_ box: DeviceErrorBox) -> DeviceErrorBox? {
        slot.withLock { collecting in
            let earlier = collecting
            collecting = box
            return earlier
        }
    }

    /// Puts `earlier` back in the slot, whatever is in it now — nil for the ordinary case of
    /// the outermost boundary finishing.
    static func disarm(restoring earlier: DeviceErrorBox?) {
        slot.withLock { $0 = earlier }
    }

    /// Hands `message` to whatever box is armed, and says what it was. Looking the box up and
    /// asking it whether this is the first are one call, so the handler takes the lock once.
    static func record(_ message: String) -> Reception {
        guard let box = slot.withLock({ $0 }) else { return .unscoped }
        return box.record(message) ? .recorded : .echo
    }
}
