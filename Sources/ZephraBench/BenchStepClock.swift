import Foundation
import ZephraCore

/// Times the denoising loop by watching progress callbacks.
///
/// The pipeline reports a step just before it runs it, so the gap between one callback and the
/// next is the cost of one step. The decoding callback closes the last step. Held by a class
/// because the progress handler is called synchronously from inside the generation and has to
/// accumulate into shared state.
final class BenchStepClock {
    private var marks: [ContinuousClock.Instant] = []

    /// Notes the time if this phase bounds a denoising step.
    func record(_ phase: GenerationPhase) {
        switch phase {
        case .denoising, .decoding:
            marks.append(ContinuousClock.now)
        case .preparing, .encodingText, .saving:
            break
        }
    }

    /// One entry per completed denoising step, in seconds.
    var intervals: [Double] {
        zip(marks, marks.dropFirst()).map { ($1 - $0).seconds }
    }
}
