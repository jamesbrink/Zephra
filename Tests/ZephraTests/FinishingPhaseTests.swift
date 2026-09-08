import Testing
import ZephraCore
import ZephraEngine

@testable import Zephra

/// The stretch between the last step and the result: the run is not over when the steps are.
@Suite("Finishing a run after its last step")
struct FinishingPhaseTests {
    private let decoding = GenerationProgressEvent(phase: .decoding, fraction: 1)

    @Test("the decode and the save are the finishing phases; the loop and what precedes it are not")
    func whichPhasesFinish() {
        #expect(EngineState.generating(decoding).isFinishing)
        #expect(EngineState.generating(GenerationProgressEvent(phase: .saving, fraction: 1)).isFinishing)
        #expect(!EngineState.generating(GenerationProgressEvent(phase: .denoising(step: 8, of: 8), fraction: 1)).isFinishing)
        #expect(!EngineState.generating(GenerationProgressEvent(phase: .encodingText, fraction: 0)).isFinishing)
        #expect(!EngineState.ready.isFinishing)
    }

    @Test("a clip is developed and encoded; a picture is developed and saved")
    func wordedForTheKindOfRun() {
        let state = EngineState.generating(decoding)
        #expect(state.detail(clip: true) == "Developing the clip")
        #expect(state.detail == "Developing the image")
        #expect(state.subtitle(clip: true) == "Generating · developing the clip")
        let saving = EngineState.generating(GenerationProgressEvent(phase: .saving, fraction: 1))
        #expect(saving.generationPhase(clip: true) == "Encoding the clip")
        #expect(saving.generationPhase(clip: false) == "Saving")
    }

    @Test("the pace and the countdown belong to the loop, not to the decode that follows it")
    func thePaceStaysWithTheLoop() {
        let paced = EngineState.generating(GenerationProgressEvent(phase: .decoding, fraction: 1, secondsPerStep: 7))
        #expect(paced.detail == "Developing the image")
        let looping = EngineState.generating(
            GenerationProgressEvent(phase: .denoising(step: 2, of: 8), fraction: 0.125, secondsPerStep: 7))
        #expect(looping.detail == "Step 2 of 8 · 7.0 s/step · ~42 s left")
    }

    @Test("the store names the finishing phase for the run it holds, and only then")
    func theStoreNamesIt() {
        let clip = InterfacePreview.queuedRun(of: 1, steps: 8, frames: 49)
        let store = GenerationStore.preview(state: .generating(decoding), running: clip[0])
        #expect(store.runMakesClip)
        #expect(store.finishingPhase == "Developing the clip")
        #expect(store.windowSubtitle == "Generating · developing the clip")

        let picture = InterfacePreview.queuedRun(of: 1, steps: 4)
        let developing = GenerationStore.preview(state: .generating(decoding), running: picture[0])
        #expect(!developing.runMakesClip)
        #expect(developing.finishingPhase == "Developing the image")

        let looping = GenerationStore.preview(
            state: .generating(GenerationProgressEvent(phase: .denoising(step: 3, of: 4), fraction: 0.5)),
            running: picture[0])
        #expect(looping.finishingPhase == nil)
    }
}
