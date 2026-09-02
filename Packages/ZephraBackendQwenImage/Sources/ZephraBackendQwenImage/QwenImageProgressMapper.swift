import Foundation
import QwenImage
import ZephraCore

/// Turns the pipeline's progress into the app's own progress vocabulary.
nonisolated enum QwenImageProgressMapper {
    /// Rewrites one pipeline update as a `GenerationProgressEvent`.
    ///
    /// Steps are shown one-based, because that is how a person counts them, while the fraction
    /// stays at the honest completed share. `secondsPerStep` is left nil on purpose: the engine
    /// layer owns timing, because only it sees the whole run.
    static func event(from progress: QwenImageGenerationProgress) -> GenerationProgressEvent {
        GenerationProgressEvent(
            phase: phase(from: progress.stage),
            fraction: fraction(of: progress.stage),
            secondsPerStep: nil
        )
    }

    private static func phase(from stage: QwenImageGenerationProgress.Stage) -> GenerationPhase {
        switch stage {
        case .loading: .preparing
        case .encodingPrompt: .encodingText
        case .denoising(let step, let total): .denoising(step: step + 1, of: total)
        case .decoding: .decoding
        }
    }

    private static func fraction(of stage: QwenImageGenerationProgress.Stage) -> Double {
        switch stage {
        case .loading: 0
        case .encodingPrompt: 0
        case .denoising(let step, let total): total > 0 ? Double(step) / Double(total) : 0
        case .decoding: 1
        }
    }
}
