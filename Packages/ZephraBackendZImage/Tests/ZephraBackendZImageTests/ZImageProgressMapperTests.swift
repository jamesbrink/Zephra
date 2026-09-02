import Testing
import ZephraCore

@testable import ZImage
@testable import ZephraBackendZImage

/// `GenerationProgress`'s memberwise initializer is internal to the vendored package, hence
/// the `@testable import ZImage` above rather than a public construction.
private func progress(
    _ stage: ZImagePipeline.GenerationProgress.Stage,
    step: Int,
    of total: Int
) -> ZImagePipeline.GenerationProgress {
    ZImagePipeline.GenerationProgress(stage: stage, stepIndex: step, totalSteps: total)
}

@Suite("ZImageProgressMapper")
struct ZImageProgressMapperTests {
    @Test(
        "every loading stage collapses to preparing",
        arguments: [
            ZImagePipeline.GenerationProgress.Stage.loadingModel,
            .loadingTransformer,
            .loadingVAE,
            .loadingLoRA,
        ]
    )
    func loadingStagesArePreparing(stage: ZImagePipeline.GenerationProgress.Stage) {
        #expect(ZImageProgressMapper.event(from: progress(stage, step: 0, of: 1)).phase == .preparing)
    }

    @Test("the remaining stages map one to one")
    func remainingStagesMapDirectly() {
        #expect(
            ZImageProgressMapper.event(from: progress(.encodingText, step: 0, of: 9)).phase
                == .encodingText
        )
        #expect(ZImageProgressMapper.event(from: progress(.decoding, step: 9, of: 9)).phase == .decoding)
        #expect(ZImageProgressMapper.event(from: progress(.saving, step: 9, of: 9)).phase == .saving)
    }

    @Test("denoising counts the step being worked on, not the ones finished")
    func denoisingStepIsOneBased() {
        #expect(
            ZImageProgressMapper.event(from: progress(.denoising, step: 0, of: 9)).phase
                == .denoising(step: 1, of: 9)
        )
        #expect(
            ZImageProgressMapper.event(from: progress(.denoising, step: 8, of: 9)).phase
                == .denoising(step: 9, of: 9)
        )
    }

    @Test("the fraction stays the honest completed share, a step behind the label")
    func fractionTracksCompletedSteps() {
        let start = ZImageProgressMapper.event(from: progress(.denoising, step: 0, of: 9))
        #expect(start.fraction == 0)
        let last = ZImageProgressMapper.event(from: progress(.denoising, step: 8, of: 9))
        #expect(abs(last.fraction - 8.0 / 9.0) < 1e-12)
    }

    @Test("the fraction never leaves 0...1, including the zero-step guard")
    func fractionStaysInBounds() {
        let stages: [ZImagePipeline.GenerationProgress.Stage] = [
            .loadingModel, .encodingText, .denoising, .decoding, .saving,
        ]
        for stage in stages {
            for step in 0...9 {
                let fraction = ZImageProgressMapper.event(from: progress(stage, step: step, of: 9))
                    .fraction
                #expect(fraction >= 0 && fraction <= 1)
            }
        }
        #expect(ZImageProgressMapper.event(from: progress(.denoising, step: 3, of: 0)).fraction == 0)
    }

    @Test("timing is left to the engine, which is the only layer that sees a whole run")
    func secondsPerStepIsAlwaysAbsent() {
        #expect(ZImageProgressMapper.event(from: progress(.denoising, step: 4, of: 9)).secondsPerStep == nil)
        #expect(ZImageProgressMapper.event(from: progress(.decoding, step: 9, of: 9)).secondsPerStep == nil)
    }
}
