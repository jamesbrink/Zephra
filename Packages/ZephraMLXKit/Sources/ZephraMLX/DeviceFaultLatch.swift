import Synchronization

/// What the GPU has done to this process so far, and whether it is still talking to it.
///
/// One fault is a run. An ignored submission is the launch: the driver has put this process's
/// device client on an ignore list and completes its command buffers without running them, and
/// no published account has a process coming back from that without being relaunched — model
/// eviction, a released allocator cache and a rebuilt backend have each been measured doing
/// nothing. So the first `.lost` is remembered here for the rest of the process, and the
/// boundary reads it rather than deciding afresh each time.
///
/// The *first* fault is kept beside it because an ignored submission is never the first error:
/// something was blamed before it, and a log that carries only the code 4 sends diagnosis to
/// whatever the process happened to be doing rather than to the fault that poisoned it.
///
/// An instance rather than a global, so a suite can drive one without latching the process it
/// is running in; `DeviceFaultSink` holds the one the installed handler writes to.
public final class DeviceFaultLatch: Sendable {
    /// What one latch remembers, under one lock.
    private struct Held: Sendable {
        var first: DeviceFaultKind?
        var firstMessage: String?
        var lost = false
    }

    private let held = Mutex(Held())

    public init() {}

    /// Files one message MLX raised and says whether this is the moment the device was lost —
    /// true exactly once per latch, for the first ignored submission.
    ///
    /// A message that is not a command-buffer failure is not a device fault and is filed as
    /// nothing: a shape error and a failed library build reach the same handler.
    @discardableResult
    public func record(_ message: String) -> Bool {
        guard let kind = DeviceFaultKind(message: message) else { return false }
        return held.withLock { held in
            if held.first == nil {
                held.first = kind
                held.firstMessage = message
            }
            guard kind.isLost, !held.lost else { return false }
            held.lost = true
            return true
        }
    }

    /// Whether the driver has stopped running this process's command buffers.
    public var isLost: Bool { held.withLock { $0.lost } }

    /// The first device fault of this process, or nil while there has been none.
    public var firstKind: DeviceFaultKind? { held.withLock { $0.first } }

    /// That fault's own text, for the log line that names what came before the refusal.
    public var firstMessage: String? { held.withLock { $0.firstMessage } }
}
