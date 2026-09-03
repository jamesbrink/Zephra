import Flux2
import ZephraCore

/// Translates the pipeline's stages into the engine's progress events.
enum Flux2ProgressMapper {
    /// The event for one stage. Steps are reported one-based to the person watching, while the
    /// fraction stays the honest completed share. `secondsPerStep` is left nil: the engine's
    /// timer annotates it, because only the engine sees the whole run.
    static func event(from progress: Flux2GenerationProgress) -> GenerationProgressEvent {
        switch progress.stage {
        case .loading:
            GenerationProgressEvent(phase: .preparing, fraction: 0)
        case .encodingPrompt, .encodingReference:
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
