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

    /// The first step the model actually ran, counting from one.
    ///
    /// Normally 1. With a reference image the loop joins the schedule partway down, and this is
    /// where — observed from what the backend reported rather than recomputed here, because the
    /// ladder that decides it belongs to the family, not to the benchmark.
    private(set) var firstStep: Int?

    /// Seconds each preview frame took to decode, in the order they were made.
    private(set) var previewSeconds: [Double] = []
    /// The last frame the run reported, kept so the benchmark can write it out and be looked at.
    private(set) var lastPreview: GenerationPreview?

    /// Notes the time if this update bounds a denoising step.
    ///
    /// An update carrying a frame is not one of those. A frame is reported after its step has
    /// finished rather than before the next one starts, so counting it as a step boundary would
    /// split one step into two and halve the reported pace. Its own cost is tallied instead.
    func record(_ event: GenerationProgressEvent) {
        if let preview = event.preview {
            previewSeconds.append(preview.duration.seconds)
            lastPreview = preview
            return
        }
        switch event.phase {
        case .denoising(let step, _):
            if firstStep == nil { firstStep = step }
            marks.append(ContinuousClock.now)
        case .decoding:
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
