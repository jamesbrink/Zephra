import ZImage

/// The one call site `GPUFaultProbe` is reached through. Debug-only, so a Release build carries
/// neither this file's body nor `GPUFaultProbe` itself.
#if DEBUG
extension ZImageBackend {
    /// Fires `GPUFaultProbe` when `progress` reports the denoising step
    /// `ZEPHRA_FAULT_GPU_AT_STEP` named, through `InferenceEnvironment.faultGPUAtStep`.
    ///
    /// Compared against `progress.stepIndex` itself — the step index the environment variable
    /// is named for — rather than the one `ZImageProgressMapper` shows the user, which is that
    /// value plus one.
    func fireFaultProbeIfNeeded(for progress: ZImagePipeline.GenerationProgress) {
        guard let target = environment.faultGPUAtStep,
            case .denoising = progress.stage,
            progress.stepIndex == target
        else { return }
        GPUFaultProbe.fire()
    }
}
#endif
