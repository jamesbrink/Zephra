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
///
/// Recorded as that run's, but **not cancelled as that run's task**. The slot carries the task
/// the boundary was armed on beside the box, and the handler cancels only where the fault was
/// raised on that same task. Zephra's own unscoped device work is the reason: the wired-limit
/// reservation runs its tickets on a `Task.detached` of its own, and cancelling *that* would
/// leave the residency set at whatever it was and never set it again, for the rest of the
/// launch, because of a fault in some other task's run.
enum DeviceFaultSink {
    /// What one raised error turned out to be.
    enum Reception {
        /// The first fault of a boundary that is collecting, raised on the very task that
        /// armed it. Worth a log line and a cancel.
        case recorded
        /// The first fault of a boundary that is collecting, raised somewhere else: another
        /// task's MLX work while this boundary happened to be open. The run is still lost —
        /// the device faulted under it — but the task that raised it is not the run's and is
        /// left to finish.
        case recordedOffTask
        /// A later error inside the same boundary, which the first one poisoned into being.
        case echo
        /// Raised where no boundary was collecting: the allocator's cache, the wired-limit
        /// reservation, a device query before any model is up.
        case unscoped
    }

    /// One boundary's box and the task it was armed on, which is the task the run unwinds by
    /// being cancelled.
    struct Armed {
        let box: DeviceErrorBox
        /// `UnsafeCurrentTask` is `Hashable` over the task object itself, so this is the same
        /// number every time the same live task asks and a different one for any other. It is
        /// only ever compared against another reading taken while both tasks are alive, so a
        /// task whose storage is later reused cannot be mistaken for this one.
        let task: Int?
    }

    private static let slot = Mutex<Armed?>(nil)

    /// Collects into `box` from now on, charged to the calling task, and hands back what was
    /// armed before for the caller to put back when it is done.
    static func arm(_ box: DeviceErrorBox) -> Armed? {
        let armed = Armed(box: box, task: currentTask())
        return slot.withLock { collecting in
            let earlier = collecting
            collecting = armed
            return earlier
        }
    }

    /// Puts `earlier` back in the slot, whatever is in it now — nil for the ordinary case of
    /// the outermost boundary finishing.
    static func disarm(restoring earlier: Armed?) {
        slot.withLock { $0 = earlier }
    }

    /// Hands `message` to whatever box is armed, and says what it was. Looking the box up and
    /// asking it whether this is the first are one call, so the handler takes the lock once.
    static func record(_ message: String) -> Reception {
        guard let armed = slot.withLock({ $0 }) else { return .unscoped }
        guard armed.box.record(message) else { return .echo }
        guard let task = armed.task, task == currentTask() else { return .recordedOffTask }
        return .recorded
    }

    /// The task the calling thread is running, or nil where it is running none — a thread with
    /// no task matches no boundary, and there is nothing on it to cancel anyway.
    private static func currentTask() -> Int? {
        withUnsafeCurrentTask { $0?.hashValue }
    }
}
