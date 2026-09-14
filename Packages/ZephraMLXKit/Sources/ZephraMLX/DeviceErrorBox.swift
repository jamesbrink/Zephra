import Synchronization

/// The first device error one `catchingDeviceErrors` boundary saw.
///
/// MLX hands its errors to a handler that cannot throw and may be called from any thread, so
/// the message is put down here and read once the work has unwound. The *first* is what is
/// kept: a fault poisons every array the run is holding, so what follows it is an echo of the
/// one that matters, and the remedy is the same either way.
final class DeviceErrorBox: Sendable {
    private let storage = Mutex<String?>(nil)

    /// Records `message` if nothing has been recorded yet, and says whether this was the first
    /// — which is what keeps a chain of echoes to one log line and one cancellation.
    @discardableResult
    func record(_ message: String) -> Bool {
        storage.withLock { stored in
            guard stored == nil else { return false }
            stored = message
            return true
        }
    }

    /// The first message recorded, or nil while the boundary has seen no fault at all.
    var firstMessage: String? { storage.withLock { $0 } }
}
