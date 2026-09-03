import Foundation
import Synchronization
import ZephraCore

/// The dial and the tally sheet for `MockUpscaler`.
///
/// An upscaler factory has to be `@Sendable`, so a test cannot hand it a prepared upscaler. It
/// hands it this instead, exactly as `MockBackendControl` does for the backend: a lock-protected
/// value the test can change between calls and read from any thread.
final class MockUpscalerControl: Sendable {
    /// Everything the mock reads before acting, and everything it records afterwards.
    struct Settings: Sendable {
        /// Thrown from `upscale` when set.
        var error: UpscaleError?
        /// How long each tile pretends to take, so a test can cancel while one is under way.
        /// Zero skips the sleep entirely.
        var tileDelay: Duration = .zero
        /// How many tiles the picture is reported as being cut into.
        var tiles = 3
        /// How many times `upscale` was called.
        var upscales = 0
        /// How many times `unload` was called.
        var unloads = 0
        /// The factor of the last upscale asked for.
        var lastFactor: Int?
        /// How many tiles have been reported since the last reset.
        var tilesEmitted = 0
    }

    private let storage = Mutex(Settings())

    /// A consistent copy of the current settings and counters.
    var settings: Settings { storage.withLock { $0 } }

    /// Changes the settings or counters under the lock.
    func update(_ change: (inout Settings) -> Void) {
        storage.withLock { change(&$0) }
    }
}
