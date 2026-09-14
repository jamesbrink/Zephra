import MLX
import MLXFast
import os

/// Provokes a real GPU fault on demand, so the completion-queue path
/// (`InferenceRuntime.catchingDeviceErrors`, `DeviceFaultSink`, `MLXRuntime.installErrorLogging`)
/// can be proven end to end without waiting for the field's own Metal driver hang.
///
/// It commits a Metal command buffer running a kernel that never finishes, so the GPU watchdog
/// times it out (`kIOGPUCommandBufferCallbackErrorTimeout`) and the driver resets the device —
/// the exact failure a field GPU fault leaves behind. Every other app using the GPU at that
/// moment loses its own in-flight frames; they are innocent victims of a reset this process
/// asked for on purpose. Never run this on a Mac anyone else is using at the time.
///
/// Debug-only, reached only through `ZEPHRA_FAULT_GPU_AT_STEP` at `ZImageBackend`'s one call
/// site (`ZImageBackend+FaultProbe.swift`), and never wired to any UI.
#if DEBUG
enum GPUFaultProbe {
    private static let log = Logger(subsystem: "io.zephra", category: "fault-probe")

    /// Commits a kernel that runs 2^40 turns of a hash whose result is stored, then evaluates
    /// its output so the command buffer is actually submitted rather than left as an
    /// unevaluated graph node.
    ///
    /// Not an infinite loop. The first two hand runs used one, and the Metal compiler removed
    /// it both times: a loop with no exit and no side effect is undefined behaviour it may
    /// delete, and hoisting the flag read out of the second version left exactly that. A
    /// bounded loop of real work is something it has to run, and 2^40 dependent multiplies on
    /// one thread is hours; the trip count is read from an array holding 0 so the count cannot
    /// be folded, and the hash cannot be closed over. The watchdog ends it in seconds.
    static func fire() {
        let flag = MLXArray.zeros([1], dtype: .int32)
        let kernel = MLXFast.metalKernel(
            name: "zephra_gpu_fault_probe",
            inputNames: ["flag"],
            outputNames: ["out"],
            source: """
                uint elem = thread_position_in_grid.x;
                uint h = 2166136261u;
                ulong turns = 1ul << (40 + flag[0]);
                for (ulong i = 0; i < turns; i++) {
                    h = (h ^ (uint)i) * 16777619u;
                }
                out[elem] = (int)h;
                """
        )
        let started = ContinuousClock.now
        log.error("GPU fault probe firing: a command buffer the watchdog has to end")
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
