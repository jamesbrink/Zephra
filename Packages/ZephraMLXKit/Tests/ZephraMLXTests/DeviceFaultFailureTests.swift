import Testing
import ZephraCore

@testable import ZephraMLX

/// Which `BackendError` one caught fault becomes.
///
/// The engine runs a job again by itself only for `.deviceVictim`, so the victim has to be told
/// apart from every other command-buffer failure here, and nothing else may be mistaken for one.
/// The process latch is never closed by these messages: none of them is an ignored submission.
@Suite("Turning a caught fault into a failure")
struct DeviceFaultFailureTests {
    @Test("an innocent victim is a victim, and says so with the runtime's own text")
    func aVictimIsAVictim() {
        let message = DeviceFaultKindTests.victim
        #expect(MLXInferenceRuntime.failure(message) == .deviceVictim(message))
    }

    @Test("every other fault, and an error that is no fault at all, is a lost run as before")
    func everythingElseIsALostRun() {
        for message in [
            DeviceFaultKindTests.hang, DeviceFaultKindTests.timeout,
            DeviceFaultKindTests.pageFault, "[METAL] Command buffer execution failed: Unknown.",
            "[broadcast_shapes] Shapes (2) and (3) cannot be broadcast.",
        ] {
            #expect(MLXInferenceRuntime.failure(message) == .deviceFailed(message))
        }
    }
}
