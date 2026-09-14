import Synchronization
import Testing
import ZephraCore

@testable import Zephra

/// Where the app's one runtime handle sends a device-error boundary.
///
/// MLX's handler stack is process-wide, so opening the boundary on the first runtime opens it
/// for every family's work. Pinned because the protocol carries a default that quietly runs
/// the body with no boundary at all: a combined runtime that forgot to forward would fail no
/// test and disable the feature in the shipping app.
@Suite("the combined runtime's device-error boundary")
struct CombinedRuntimeDeviceErrorTests {
    @Test("the boundary is opened on the first runtime, and only on that one")
    func boundaryGoesToTheFirstRuntime() async throws {
        let first = CountingRuntime()
        let second = CountingRuntime()
        let combined = CombinedInferenceRuntime([first, second])

        let answer = try await combined.catchingDeviceErrors { 7 }

        #expect(answer == 7, "the body's own answer must come back untouched")
        #expect(first.boundaries == 1)
        #expect(second.boundaries == 0, "one handler stack wants one boundary")
    }

    @Test("what the boundary threw is what the caller sees")
    func theBoundarysErrorIsRethrown() async throws {
        let first = CountingRuntime()
        first.faults = true
        let combined = CombinedInferenceRuntime([first, CountingRuntime()])

        await #expect(throws: BackendError.deviceFailed("discarded")) {
            try await combined.catchingDeviceErrors { 7 }
        }
    }

    @Test("the global backstop is installed on the first runtime")
    func loggingGoesToTheFirstRuntime() {
        let first = CountingRuntime()
        let second = CountingRuntime()
        CombinedInferenceRuntime([first, second]).installDeviceErrorLogging()
        #expect(first.installs == 1)
        #expect(second.installs == 0)
    }

    /// A runtime with no GPU behind it that records what it was asked to open and install, and
    /// can be told to answer the way a faulted device does.
    ///
    /// `nonisolated` for the reason `CombinedInferenceRuntime` is: under this target's
    /// main-actor default, an isolated conformance witnesses nothing and every call lands on
    /// the protocol's own defaults, which is a stub that records nothing and a test that
    /// passes whatever the app does.
    private nonisolated final class CountingRuntime: InferenceRuntime, @unchecked Sendable {
        private let openings = Mutex(0)
        private let installations = Mutex(0)
        var faults = false

        /// How many boundaries were opened on this runtime.
        var boundaries: Int { openings.withLock { $0 } }
        /// How many times this runtime was asked for the global backstop.
        var installs: Int { installations.withLock { $0 } }

        func synchronize() {}
        func setCacheLimit(bytes: Int) {}
        func setMemoryLimit(bytes: Int) {}
        func deviceSummary() -> String { "counting" }
        func memorySnapshot() -> MemorySnapshot { .zero }
        func setVAETileSize(_ tile: Int?) {}
        func vaeTileSize() -> Int? { nil }

        func installDeviceErrorLogging() {
            installations.withLock { $0 += 1 }
        }

        nonisolated(nonsending) func catchingDeviceErrors<R>(_ body: nonisolated(nonsending) () async throws -> R)
            async throws -> R
        {
            openings.withLock { $0 += 1 }
            let value = try await body()
            if faults { throw BackendError.deviceFailed("discarded") }
            return value
        }
    }
}
