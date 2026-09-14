import MLX
import MLXFast
import os

/// Provokes a real GPU fault on demand, so the completion-queue path
/// (`InferenceRuntime.catchingDeviceErrors`, `DeviceFaultSink`, `MLXRuntime.installErrorLogging`)
/// can be proven end to end without waiting for the field's own Metal driver hang.
///
/// It commits a Metal command buffer whose kernel reads an address no page table maps, so the
/// GPU takes an MMU fault and the driver resets the device — the exact failure the field crash
/// was, an "MMU interrupt" in the gpuEvent report. Every other app using the GPU at that
/// moment loses its own in-flight frames; they are innocent victims of a reset this process
/// asked for on purpose. Never run this on a Mac anyone else is using at the time.
///
/// Debug-only, reached only through `ZEPHRA_FAULT_GPU_AT_STEP` at `ZImageBackend`'s one call
/// site (`ZImageBackend+FaultProbe.swift`), and never wired to any UI.
#if DEBUG
enum GPUFaultProbe {
    private static let log = Logger(subsystem: "io.zephra", category: "fault-probe")

    /// Commits a kernel that reads 256 GB past a four-byte buffer and stores what it found, then
    /// evaluates the output so the command buffer is actually submitted rather than left as an
    /// unevaluated graph node.
    ///
    /// A page fault, not a hang. The first three hand runs tried a kernel that never finishes:
    /// an infinite loop is undefined behaviour the Metal compiler deleted twice, and bounded
    /// work of hours ran for nine minutes on an M4 mini with no watchdog ending it, the app
    /// stuck inside `eval`. An access outside every mapping faults at once. The offset is read
    /// from an array holding 0, so the compiler cannot prove it out of bounds and drop the
    /// access, and the value read is stored, so it cannot drop the read.
    static func fire() {
        let flag = MLXArray.zeros([1], dtype: .int32)
        let kernel = MLXFast.metalKernel(
            name: "zephra_gpu_fault_probe",
            inputNames: ["flag"],
            outputNames: ["out"],
            source: """
                uint elem = thread_position_in_grid.x;
                ulong far = (1ul << 36) + (ulong)flag[0];
                out[elem] = out[far] + flag[elem];
                """
        )
        let started = ContinuousClock.now
        log.error("GPU fault probe firing: a command buffer that reads an unmapped address")
        let result = kernel(
            [flag],
            grid: (1, 1, 1),
            threadGroup: (1, 1, 1),
            outputShapes: [[1]],
            outputDTypes: [.int32]
        )
        MLX.eval(result)
        let elapsed = ContinuousClock.now - started
        log.error("GPU fault probe returned after \(elapsed.components.seconds, privacy: .public) s")
    }
}
#endif
