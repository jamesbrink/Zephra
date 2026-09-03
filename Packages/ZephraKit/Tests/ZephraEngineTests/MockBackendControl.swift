import Synchronization
import ZephraCore

/// The dial and the tally sheet for `MockBackend`.
///
/// A backend factory has to be `@Sendable`, so a test cannot hand it a prepared backend object.
/// It hands it this instead: a lock-protected value the test can change between calls and read
/// from any thread, which is also what makes "fail the load, then fix it and retry" expressible.
final class MockBackendControl: Sendable {
    /// Everything the mock reads before acting, and everything it records afterwards.
    struct Settings: Sendable {
        /// Thrown from `load` when set.
        var loadError: BackendError?
        /// Thrown from `generate` when set.
        var generateError: BackendError?
        /// How long each denoising step pretends to take. Zero skips the sleep entirely.
        var stepDelay: Duration = .milliseconds(10)
        /// How long `load` pretends to take, so a test can cancel while it is under way.
        /// Zero skips the sleep entirely.
        var loadDelay: Duration = .zero
        /// Overrides the step count in the request, for a mock that ignores what it is asked.
        var stepOverride: Int?
        /// How many build progress events `build` reports. Zero means the download is what
        /// gets loaded, which is what every family but one does.
        var buildEvents = 0
        /// How long each build event pretends to take, so a test can cancel during a build.
        var buildDelay: Duration = .zero
        /// The settings of the last generation the backend was asked for, so a test can assert
        /// what actually reached it rather than what the store thinks it sent.
        var lastSettings: GenerationSettings?
        /// What `availability(of:)` answers per descriptor id. Anything absent is `.available`.
        var availability: [String: ModelAvailability] = [:]
        /// How many times `load` was called.
        var loads = 0
        /// How many times `unload` was called.
        var unloads = 0
        /// How many times `build` was asked to do something.
        var builds = 0
        /// How many times `availability(of:)` was asked.
        var availabilityChecks = 0
        /// How many times `generate` was called, warm-up included.
        var generations = 0
        /// How many denoising steps have been reported since the last reset.
        var stepsEmitted = 0
    }

    private let storage = Mutex(Settings())

    /// A consistent copy of the current settings and counters.
    var settings: Settings { storage.withLock { $0 } }

    /// Changes the settings or counters under the lock.
    func update(_ change: (inout Settings) -> Void) {
        storage.withLock { change(&$0) }
    }
}
