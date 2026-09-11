import LTX2
import ZephraCore

/// Translates the pipeline's stages into the engine's progress events.
enum LTX2ProgressMapper {
    /// The event for one stage. The pipeline reports steps one-based already, so the fraction
    /// is the share completed before this step. `secondsPerStep` is left nil: the engine's
    /// timer annotates it, because only the engine sees the whole run.
    static func event(from progress: LTX2GenerationProgress) -> GenerationProgressEvent {
        switch progress.stage {
        case .loading:
            GenerationProgressEvent(phase: .preparing, fraction: 0)
        case .encodingPrompt:
            GenerationProgressEvent(phase: .encodingText, fraction: 0)
        case .denoising(let step, let total):
            GenerationProgressEvent(
                phase: .denoising(step: step, of: total),
                fraction: Double(step - 1) / Double(max(total, 1)))
        case .decoding, .decodingAudio:
            GenerationProgressEvent(phase: .decoding, fraction: 1)
        }
    }
}
