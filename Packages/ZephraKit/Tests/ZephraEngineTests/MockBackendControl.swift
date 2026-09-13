import Foundation
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
        var downloadGate: (@Sendable (ModelDescriptor) async throws -> Void)?
        var loadGate: (@Sendable (ModelDescriptor) async -> Void)?
        var ignoresLoadCancellation = false
        var downloadDelay: Duration = .zero
        var loadDelay: Duration = .zero
        /// Overrides the step count in the request, for a mock that ignores what it is asked.
        var stepOverride: Int?
        /// How many build progress events `build` reports. Zero means the download is what
        /// gets loaded, which is what every family but one does.
        var buildEvents = 0
        /// How long each build event pretends to take, so a test can cancel during a build.
        var buildDelay: Duration = .zero
        var buildGate: (@Sendable () async -> Void)?
        /// The settings of the last generation the backend was asked for, so a test can assert
        /// what actually reached it rather than what the store thinks it sent.
        var lastSettings: GenerationSettings?
        /// The folder the last `ensureAvailable` was told to keep models in, so a test can
        /// assert that a chosen folder actually reached the backend.
        var lastLocations: ModelLocations?
        /// Where the last `load` was told to keep the weights, so a test can assert the
        /// policy's answer actually reached the backend.
        var lastResidency: WeightResidency?
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
        /// Whether every denoising step carries a preview frame. The real backends throttle
        /// theirs to one every three quarters of a second; a mock that has to be waited for
        /// would make every test that touches a frame a slow one.
        var previewsEveryStep = false
        /// How many preview frames have been reported.
        var previewsEmitted = 0
        /// The claim the last `ensureAvailable` was handed, so a test can ask the pool whether
        /// it is still held once the weights are gone.
        var lastAcquisitionID: UUID?
        /// A backend that never looks for a cancel after its last step, so a stop pressed
        /// during the decode reaches the store with finished bytes in hand.
        var ignoresFinalCancellation = false
        /// How long the pretend decode after the last step takes. Zero skips it.
        var decodeDelay: Duration = .zero
        /// The VAE tile `MockInferenceRuntime` was last told to decode at.
        var vaeTile: Int?
        /// The tile in force when the last `generate` began, warm-up included: what a real
        /// backend's decode would have read.
        var tileAtGenerate: Int?
        /// How many times the runtime was asked to hand its cache back, which the actor does
        /// once per unload and only after the backend has dropped its arrays.
        var cacheReleases = 0
        /// What the Mac is said to have free, which `DialMachineMemory` answers with, so a
        /// test can starve the machine between one attempt and the next.
        var machine: MachineMemory?
        /// What the allocator says it is holding, for the memory guard to read.
        var memory: MemorySnapshot = .zero
    }

    private let storage = Mutex(Settings())

    /// A consistent copy of the current settings and counters.
    var settings: Settings { storage.withLock { $0 } }

    /// Changes the settings or counters under the lock.
    func update(_ change: (inout Settings) -> Void) {
        storage.withLock { change(&$0) }
    }
}
