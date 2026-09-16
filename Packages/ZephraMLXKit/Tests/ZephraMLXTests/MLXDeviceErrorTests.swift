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
///
/// That only orders *this* suite. The handler is the process's, so any other suite in this
/// package raising an MLX error while a boundary here is open would have it recorded into this
/// boundary's box — which is the boundary working as designed, and a false failure here. Hence
/// the assertions below check the recorded text rather than merely that something was recorded:
/// a stray error from elsewhere would not be about broadcasting these shapes. `make test-mlx`
/// runs each package's suites serially for a related reason (see AGENTS.md).
@Suite("The real-MLX device-error boundary", .serialized)
struct MLXDeviceErrorTests {
    /// Evaluates two arrays MLX cannot broadcast together, which raises on this thread.
    private func raiseShapeMismatch() {
        let a = MLXArray(0..<10, [2, 5])
        let b = MLXArray(0..<15, [3, 5])
        MLX.eval(a + b)
    }

    /// Fails unless `error` is the device failure this suite's own mismatch raises, rather than
    /// something another suite left in the boundary's box.
    private func expectShapeMismatch(_ error: any Error, _ comment: Comment) {
        guard case .deviceFailed(let message)? = error as? BackendError else {
            Issue.record("expected .deviceFailed, got \(error)")
            return
        }
        #expect(message.lowercased().contains("broadcast"), comment)
    }

    @Test("a shape mismatch inside the boundary comes out as a device failure")
    func shapeMismatchBecomesDeviceFailed() async throws {
        let runtime = MLXInferenceRuntime(tile: VAETileSetting())
        do {
            try await runtime.catchingDeviceErrors { raiseShapeMismatch() }
            Issue.record("expected a device failure")
        } catch {
            expectShapeMismatch(error, "the boundary must carry MLX's own text")
        }
        // And through the real handler and the real latch: only IOGPU's own
        // `SubmissionsIgnored` ends a launch, so an error that is not a command-buffer failure
        // must never say the GPU is gone — an app that relaunched itself over a broadcast
        // error would be a fault of its own.
        #expect(!runtime.isDeviceLost)
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
                    if step == 3 { raiseShapeMismatch() }
                }
            }
            Issue.record("expected a device failure")
        } catch {
            // The boundary prefers the fault it caused over the cancellation, which is why this
            // is `.deviceFailed` rather than `CancellationError`.
            expectShapeMismatch(error, "a fault must not read as a stop")
        }
        // Iteration 3 counts (the check passes before the fault) and records the fault, which
        // cancels the task; iteration 4's own `checkCancellation` is what throws, so the count
        // never reaches 4, let alone all ten.
        #expect(iterations == 3)
    }

    @Test("a fault raised off the run's own task fails the run without cancelling that task")
    func faultOffTheRunsTaskCancelsNothing() async throws {
        let runtime = MLXInferenceRuntime(tile: VAETileSetting())
        var ranToTheEnd = false
        do {
            try await runtime.catchingDeviceErrors {
                // Zephra's unscoped device work — the wired-limit reservation — is a
                // `Task.detached` like this one. A fault it raises while a run's boundary is
                // open belongs in the run's box, because the device faulted under the run; the
                // task it was raised on is not the run's and must survive, or the reservation
                // would stop replacing the wired limit for the rest of the launch.
                ranToTheEnd = await Task.detached { [self] in
                    raiseShapeMismatch()
                    return !Task.isCancelled
                }.value
            }
            Issue.record("expected a device failure")
        } catch {
            expectShapeMismatch(error, "the run pays for a fault raised under it")
        }
        #expect(ranToTheEnd, "the fault must cancel the run's task, not the one that raised it")
    }

    @Test("a fault outside any boundary is not fatal, and leaves the slot clean")
    func errorOutsideTheBoundaryIsLoggedNotFatal() async throws {
        MLXRuntime.installErrorLogging()
        // No boundary is open, so `DeviceFaultSink` finds no box and logs the "unscoped" line
        // instead — which nothing here reads, hence the title: what is asserted is that there
        // is nothing to throw or crash, since `eval` is not a throwing call.
        raiseShapeMismatch()

        // A boundary opened afterwards still catches its own fault, which is what says the
        // unscoped fault above left the slot empty rather than wedged on a box nobody reads.
        let runtime = MLXInferenceRuntime(tile: VAETileSetting())
        do {
            try await runtime.catchingDeviceErrors { raiseShapeMismatch() }
            Issue.record("expected a device failure")
        } catch {
            expectShapeMismatch(error, "a boundary after an unscoped fault still collects")
        }
    }
}
