import Testing
import ZephraCore
import ZephraEngine

@testable import Zephra

@Suite("The words the canvas and the subtitle use for each engine state")
struct EngineStateDisplayTests {
    private let model = ModelCatalog.zImageTurbo8bit

    @Test("ready and failed are one word in the subtitle, whatever detail they carry")
    func readyAndFailedAreOneWord() {
        #expect(EngineState.ready.subtitle == "Ready")
        #expect(EngineState.failed(.noBackend(.zImage)).subtitle == "Failed")
    }

    @Test("a state with a detail joins the label and the detail, lowercasing the detail's first letter")
    func detailIsJoinedToTheLabel() {
        let state = EngineState.upscaling(UpscaleProgressEvent(completedTiles: 2, totalTiles: 8))
        #expect(state.subtitle == "Upscaling · tile 2 of 8")
        #expect(state.detail == "Tile 2 of 8")
    }

    @Test("the download subtitle names the model on its way, and only that state does")
    func downloadSubtitleNamesTheModel() {
        let downloading = EngineState.downloading(
            DownloadProgressEvent(completedFiles: 1, totalFiles: 4, fraction: 0.25))
        #expect(downloading.subtitle(for: model) == "Downloading Z-Image Turbo · 8-bit · file 1 of 4 · 25%")
        #expect(EngineState.warmingUp.subtitle(for: model) == "Warming up")
    }

    @Test("the download detail carries the rate only when there is one")
    func downloadDetailCarriesTheRateWhenKnown() {
        let quiet = EngineState.downloading(
            DownloadProgressEvent(completedFiles: 3, totalFiles: 4, fraction: 0.5))
        #expect(quiet.detail == "File 3 of 4 · 50%")
        let moving = EngineState.downloading(
            DownloadProgressEvent(completedFiles: 3, totalFiles: 4, fraction: 0.5, bytesPerSecond: 2_000_000))
        #expect(moving.detail?.contains("/s") == true)
    }

    @Test("the headline says what choosing the model costs, and which variant is being built")
    func headlinesNameTheCost() {
        let downloading = EngineState.downloading(
            DownloadProgressEvent(completedFiles: 0, totalFiles: 1, fraction: 0))
        #expect(downloading.title(for: model) == "Z-Image Turbo needs a one-time 13.3 GB download.")
        let building = EngineState.building(
            BuildProgressEvent(component: "transformer", completedComponents: 0, totalComponents: 3, fraction: 0))
        #expect(building.title(for: model) == "Building the 8-bit variant of Z-Image Turbo. This happens once.")
        #expect(EngineState.idle.title(for: model) == "Z-Image Turbo isn't loaded yet.")
    }

    @Test("ready and generating need no headline; a failure's headline is its message")
    func readyAndGeneratingHaveNoHeadline() {
        #expect(EngineState.ready.title(for: model) == nil)
        let generating = EngineState.generating(GenerationProgressEvent(phase: .preparing, fraction: 0))
        #expect(generating.title(for: model) == nil)
        let error = EngineError.noBackend(.zImage)
        #expect(EngineState.failed(error).title(for: model) == error.message)
    }

    @Test("the generating detail is the phase, the pace, and the seconds left")
    func generatingDetailReportsThePace() {
        let event = GenerationProgressEvent(
            phase: .denoising(step: 3, of: 9), fraction: 3 / 9, secondsPerStep: 2.5)
        let state = EngineState.generating(event)
        #expect(state.detail == "Step 3 of 9 · 2.5 s/step · ~15 s left")
        #expect(state.generationPhase == "Step 3 of 9")
        #expect(state.denoisingProgress?.step == 3)
        #expect(state.denoisingProgress?.total == 9)
    }

    @Test("only a download, a build, and an upscale draw a bar")
    func onlyMeasuredStatesDrawABar() {
        let building = EngineState.building(
            BuildProgressEvent(component: "vae", completedComponents: 1, totalComponents: 2, fraction: 0.5))
        #expect(building.progressFraction == 0.5)
        #expect(building.detail == "Packing the vae · 1 of 2 · 50%")
        #expect(EngineState.warmingUp.progressFraction == nil)
        let decoding = EngineState.generating(GenerationProgressEvent(phase: .decoding, fraction: 1))
        #expect(decoding.progressFraction == nil)
    }
}
