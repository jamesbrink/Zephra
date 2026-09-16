import Testing
import ZephraMLX

/// Reading the driver's verdict out of the one string MLX hands up.
///
/// Every message below is verbatim: the first two are what a 16 GB M4 mini logged on
/// 2026-09-15, and the other three are the same `%s (%08x:%s)` shape with IOGPU's own names and
/// codes for the faults the same machine's `gpuEvent` reports named. The distinction they are
/// read for is one bit wide — is this launch's GPU gone, or is this one lost run — so the
/// parser is pinned rather than trusted.
@Suite("Reading a command-buffer failure")
struct DeviceFaultKindTests {
    static let victim =
        "[METAL] Command buffer execution failed: Discarded (victim of GPU error/recovery) "
        + "(00000005:kIOGPUCommandBufferCallbackErrorInnocentVictim)."
    static let ignored =
        "[METAL] Command buffer execution failed: Ignored (for causing prior/excessive GPU "
        + "errors) (00000004:kIOGPUCommandBufferCallbackErrorSubmissionsIgnored)."
    static let hang =
        "[METAL] Command buffer execution failed: Caused GPU Hang Error "
        + "(00000003:kIOGPUCommandBufferCallbackErrorHang)."
    static let timeout =
        "[METAL] Command buffer execution failed: Caused GPU Timeout Error "
        + "(00000002:kIOGPUCommandBufferCallbackErrorTimeout)."
    static let pageFault =
        "[METAL] Command buffer execution failed: Caused GPU Address Fault Error "
        + "(0000000b:kIOGPUCommandBufferCallbackErrorPageFault)."

    @Test("each of the five the driver actually writes")
    func theFiveKinds() {
        #expect(DeviceFaultKind(message: Self.victim) == .victim)
        #expect(DeviceFaultKind(message: Self.ignored) == .lost)
        #expect(DeviceFaultKind(message: Self.hang) == .hang)
        #expect(DeviceFaultKind(message: Self.timeout) == .timeout)
        #expect(DeviceFaultKind(message: Self.pageFault) == .pageFault)
    }

    @Test("only the ignored submission ends the launch")
    func onlyIgnoredIsLost() {
        #expect(DeviceFaultKind(message: Self.ignored)?.isLost == true)
        for message in [Self.victim, Self.hang, Self.timeout, Self.pageFault] {
            #expect(DeviceFaultKind(message: message)?.isLost == false)
        }
    }

    @Test("the enum name is matched whatever its case, and a near-miss is not a match")
    func caseInsensitiveAndExact() {
        // The name as the driver writes it is mixed case; a build of macOS that wrote it any
        // other way must still be read. MLX's own prefix is its format string and does not
        // move, so it is matched as written.
        let shouted = Self.ignored.replacingOccurrences(
            of: "kIOGPUCommandBufferCallbackErrorSubmissionsIgnored",
            with: "KIOGPUCOMMANDBUFFERCALLBACKERRORSUBMISSIONSIGNORED")
        #expect(DeviceFaultKind(message: shouted) == .lost)
        let invented =
            "[METAL] Command buffer execution failed: Something New "
            + "(00000021:kIOGPUCommandBufferCallbackErrorSomethingNew)."
        #expect(DeviceFaultKind(message: invented) == .other, "an unknown code is not a loss")
        #expect(DeviceFaultKind(message: invented)?.isLost == false)
    }

    @Test("a message that is not a command-buffer failure is not a device fault at all")
    func othersAreNotFaults() {
        #expect(DeviceFaultKind(message: "Shapes (2,5) and (3,5) cannot be broadcast.") == nil)
        #expect(DeviceFaultKind(message: "[metal::malloc] Attempting to allocate 40 GB") == nil)
        #expect(DeviceFaultKind(message: "") == nil)
        // The words alone, with no prefix, are somebody quoting a log line, not MLX raising.
        #expect(DeviceFaultKind(message: "kIOGPUCommandBufferCallbackErrorSubmissionsIgnored") == nil)
    }
}

/// The latch the boundary reads: one ignored submission and this process is finished with the
/// GPU, with the fault that came before it kept beside the refusal.
@Suite("Remembering that the GPU is gone")
struct DeviceFaultLatchTests {
    @Test("a victim is remembered as the first fault and latches nothing")
    func victimDoesNotLatch() {
        let latch = DeviceFaultLatch()
        #expect(latch.record(DeviceFaultKindTests.victim) == false)
        #expect(!latch.isLost)
        #expect(latch.firstKind == .victim)
    }

    @Test("an ignored submission latches once, and keeps what came before it")
    func ignoredLatchesOnce() {
        let latch = DeviceFaultLatch()
        latch.record(DeviceFaultKindTests.victim)
        #expect(latch.record(DeviceFaultKindTests.ignored), "the first loss is worth a line")
        #expect(latch.isLost)
        #expect(latch.firstKind == .victim, "an ignored submission is never the first error")
        #expect(latch.record(DeviceFaultKindTests.ignored) == false, "and only one line")
        #expect(latch.isLost, "it never goes back")
    }

    @Test("a shape error neither latches nor counts as the first fault")
    func nonFaultsAreFiledAsNothing() {
        let latch = DeviceFaultLatch()
        #expect(latch.record("Shapes (2,5) and (3,5) cannot be broadcast.") == false)
        #expect(latch.firstKind == nil)
        #expect(!latch.isLost)
    }
}
