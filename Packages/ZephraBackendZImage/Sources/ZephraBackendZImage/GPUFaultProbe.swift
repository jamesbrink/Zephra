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
    /// Two things keep the loop alive under the Metal compiler. The condition is data-dependent,
    /// read from an array holding 0 rather than a literal, so it cannot be proved false at
    /// compile time. And the body stores to `out` every turn: a loop with no side effect is one
    /// the compiler may delete outright, and on the first hand run it did — the read was
    /// hoisted, the empty infinite loop went, and the kernel returned at once.
    static func fire() {
        let flag = MLXArray.zeros([1], dtype: .int32)
        let kernel = MLXFast.metalKernel(
            name: "zephra_gpu_fault_probe",
            inputNames: ["flag"],
            outputNames: ["out"],
            source: """
                uint elem = thread_position_in_grid.x;
                int spins = 0;
                while (flag[0] != 42) {
                    // Spin forever: flag is always zero, so this can never resolve on its own,
                    // and the store each turn is what stops the compiler deleting the loop.
                    // The GPU watchdog is what ends it, by resetting the device.
                    spins += 1;
                    out[elem] = spins;
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
