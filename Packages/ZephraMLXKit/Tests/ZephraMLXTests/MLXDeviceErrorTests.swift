import MLX
import Testing
import ZephraCore
import ZephraMLX

/// The completion-queue boundary against real MLX, not a mock: `MLXInferenceRuntime` installs
/// MLX's one process-wide error handler and turns whatever it catches into
/// `BackendError.deviceFailed`. A shape mismatch is not a GPU fault, but it reaches the same
/// handler `DeviceFaultSink` and the field's real fault would, so it is what proves the wiring
/// without needing a Mac's GPU to misbehave on demand.
///
/// `.serialized`: `DeviceFaultSink` is one process-wide slot, armed and disarmed around each
/// boundary. Swift Testing runs a suite's tests in parallel by default, and two boundaries open
/// at once would arm and disarm the same slot out of order.
@Suite("The real-MLX device-error boundary", .serialized)
struct MLXDeviceErrorTests {
    @Test("a shape mismatch inside the boundary comes out as a device failure")
    func shapeMismatchBecomesDeviceFailed() async throws {
        let runtime = MLXInferenceRuntime(tile: VAETileSetting())
        do {
            try await runtime.catchingDeviceErrors {
                let a = MLXArray(0..<10, [2, 5])
                let b = MLXArray(0..<15, [3, 5])
                MLX.eval(a + b)
            }
            Issue.record("expected a device failure")
        } catch let error as BackendError {
            guard case .deviceFailed = error else {
                Issue.record("expected .deviceFailed, got \(error)")
                return
            }
        }
        // Still here: the handler MLX would otherwise abort the process through never ran,
        // because the boundary's box caught the error first.
    }

    @Test("a fault mid-loop cancels the task, so the next check is what unwinds it")
    func cancelledLoopUnwindsAtTheNextCheck() async throws {
        let runtime = MLXInferenceRuntime(tile: VAETileSetting())
        var iterations = 0
        do {
            try await runtime.catchingDeviceErrors {
                for step in 1...10 {
                    try Task.checkCancellation()
                    iterations += 1
                    if step == 3 {
                        let a = MLXArray(0..<10, [2, 5])
                        let b = MLXArray(0..<15, [3, 5])
                        MLX.eval(a + b)
                    }
                }
            }
            Issue.record("expected a device failure")
        } catch let error as BackendError {
            guard case .deviceFailed = error else {
                Issue.record("expected .deviceFailed, got \(error)")
                return
            }
        }
        // Iteration 3 counts (the check passes before the fault) and records the fault, which
        // cancels the task; iteration 4's own `checkCancellation` is what throws, so the count
        // never reaches 4, let alone all ten. The boundary then prefers the fault it caused
        // over the cancellation, which is why the catch above sees `.deviceFailed` rather than
        // `CancellationError`.
        #expect(iterations == 3)
    }

    @Test("a fault outside any boundary is logged, not fatal, and leaves the slot clean")
    func errorOutsideTheBoundaryIsLoggedNotFatal() async throws {
        MLXRuntime.installErrorLogging()
        let a = MLXArray(0..<10, [2, 5])
        let b = MLXArray(0..<15, [3, 5])
        // No boundary is open, so `DeviceFaultSink` finds no box, logs the "unscoped" line, and
        // there is nothing here to throw or crash: `eval` is not a throwing call.
        MLX.eval(a + b)

        // A boundary opened afterwards still catches its own fault, which is what says the
        // unscoped fault above left the slot empty rather than wedged on a box nobody reads.
        let runtime = MLXInferenceRuntime(tile: VAETileSetting())
        do {
            try await runtime.catchingDeviceErrors {
                let c = MLXArray(0..<10, [2, 5])
                let d = MLXArray(0..<15, [3, 5])
                MLX.eval(c + d)
            }
            Issue.record("expected a device failure")
        } catch let error as BackendError {
            guard case .deviceFailed = error else {
                Issue.record("expected .deviceFailed, got \(error)")
                return
            }
        }
    }
}
