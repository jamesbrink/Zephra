import ZephraCore
import ZImage

/// Turns the vendored pipeline's progress reports into the app's own progress vocabulary.
nonisolated enum ZImageProgressMapper {
    /// Rewrites one pipeline update as a `GenerationProgressEvent`.
    ///
    /// The pipeline reports a step index that counts steps *finished*, so it is shown to the
    /// user as `stepIndex + 1` ("running step 3 of 9") while the fraction stays at the honest
    /// completed share. `secondsPerStep` is left nil on purpose: the engine layer owns timing,
    /// because only it sees the whole run rather than one callback at a time.
    static func event(from progress: ZImagePipeline.GenerationProgress) -> GenerationProgressEvent {
        GenerationProgressEvent(
            phase: phase(from: progress),
            fraction: progress.fractionCompleted,
            secondsPerStep: nil
        )
    }

    private static func phase(
        from progress: ZImagePipeline.GenerationProgress
    ) -> GenerationPhase {
        switch progress.stage {
        case .loadingModel, .loadingTransformer, .loadingVAE, .loadingLoRA:
            .preparing
        case .encodingText:
            .encodingText
        case .denoising:
            .denoising(step: progress.stepIndex + 1, of: progress.totalSteps)
        case .decoding:
            .decoding
        case .saving:
            .saving
        }
    }
}
