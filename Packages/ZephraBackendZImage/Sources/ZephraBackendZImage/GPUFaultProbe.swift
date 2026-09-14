import MLX
import MLXFast

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
    /// Commits a kernel that spins forever on a data-dependent condition over a zero input, then
    /// evaluates its output so the command buffer is actually submitted rather than left as an
    /// unevaluated graph node.
    ///
    /// The condition has to be data-dependent — read from an array holding 0 rather than a
    /// literal `0` — or the compiler proves the loop never exits and folds it away, and the
    /// kernel just returns instead of hanging.
    static func fire() {
        let flag = MLXArray.zeros([1], dtype: .int32)
        let kernel = MLXFast.metalKernel(
            name: "zephra_gpu_fault_probe",
            inputNames: ["flag"],
            outputNames: ["out"],
            source: """
                uint elem = thread_position_in_grid.x;
                while (flag[0] != 42) {
                    // Spin forever: flag is always zero, so this data-dependent condition can
                    // never resolve on its own. The GPU watchdog is what ends it, by resetting
                    // the device.
                }
                out[elem] = flag[elem];
                """
        )
        let result = kernel(
            [flag],
            grid: (1, 1, 1),
            threadGroup: (1, 1, 1),
            outputShapes: [[1]],
            outputDTypes: [.int32]
        )
        MLX.eval(result)
    }
}
#endif
