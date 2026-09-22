import QwenImage21
import ZephraCore

/// Translates the pipeline's stages into the engine's progress events.
enum QwenImage21ProgressMapper {
    /// The event for one stage. Steps are reported one-based to the person watching, while the
    /// fraction stays the honest completed share. `secondsPerStep` is left nil: the engine's
    /// timer annotates it, because only the engine sees the whole run.
    ///
    /// Both encoding stages read as `.encodingText`. The autoencoder's pass over the reference
    /// pictures is not text, but it is seconds of the same waiting, and the canvas has one word
    /// for the part of a run before the first step.
    static func event(from progress: QwenImage21GenerationProgress) -> GenerationProgressEvent {
        switch progress.stage {
        case .loading:
            GenerationProgressEvent(phase: .preparing, fraction: 0)
        case .encodingPrompt, .encodingReferences:
            GenerationProgressEvent(phase: .encodingText, fraction: 0)
        case .denoising(let step, let total):
            GenerationProgressEvent(
                phase: .denoising(step: step + 1, of: total),
                fraction: Double(step) / Double(max(total, 1)))
        case .decoding:
            GenerationProgressEvent(phase: .decoding, fraction: 1)
        }
    }
}
