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

    @Test("every headline names the model the way the toolbar does, variant and all")
    func headlinesNameTheVariant() {
        let building = EngineState.building(
            BuildProgressEvent(component: "transformer", completedComponents: 0, totalComponents: 3, fraction: 0))
        #expect(building.title(for: model, availability: nil) == "Building Z-Image Turbo · 8-bit. This happens once.")
        #expect(EngineState.idle.title(for: model, availability: nil) == "Z-Image Turbo · 8-bit isn't loaded yet.")
        let downloading = EngineState.downloading(
            DownloadProgressEvent(completedFiles: 0, totalFiles: 1, fraction: 0))
        #expect(downloading.title(for: model, availability: nil)?.hasPrefix("Z-Image Turbo · 8-bit needs") == true)
    }

    @Test("the download headline states the transfer's own total once it has listed itself")
    func downloadHeadlineStatesTheListedBytes() {
        let listed = EngineState.downloading(
            DownloadProgressEvent(
                completedFiles: 0, totalFiles: 1, fraction: 0, completedBytes: 0, totalBytes: 1_700_000_000))
        #expect(
            listed.title(for: model, availability: .needsDownload(bytes: 59_400_000_000))
                == "Z-Image Turbo · 8-bit needs a one-time 1.7 GB download.")
    }

    @Test("before the listing, the headline states what the disk was missing; before that, the catalog's transfer")
    func downloadHeadlineFallsBackToAvailabilityThenTheCatalog() {
        let unlisted = EngineState.downloading(
            DownloadProgressEvent(completedFiles: 0, totalFiles: 0, fraction: 0))
        #expect(
            unlisted.title(for: model, availability: .needsDownloadAndBuild(bytes: 1_700_000_000))
                == "Z-Image Turbo · 8-bit needs a one-time 1.7 GB download.")
        #expect(
            unlisted.title(for: model, availability: .needsDownload(bytes: 2_000_000_000))
                == "Z-Image Turbo · 8-bit needs a one-time 2 GB download.")
        let qwen = ModelCatalog.qwenImage2512_4bit
        let expected = "Qwen-Image 2512 · 4-bit needs a one-time \(ByteCount.gigabytes(qwen.transferBytes)) download."
        #expect(unlisted.title(for: qwen, availability: nil) == expected)
        #expect(unlisted.title(for: qwen, availability: .available) == expected)
        #expect(qwen.transferBytes > qwen.downloadBytes)
    }

    @Test("ready and generating need no headline; a failure's headline is its message")
    func readyAndGeneratingHaveNoHeadline() {
        #expect(EngineState.ready.title(for: model, availability: nil) == nil)
        let generating = EngineState.generating(GenerationProgressEvent(phase: .preparing, fraction: 0))
        #expect(generating.title(for: model, availability: nil) == nil)
        let error = EngineError.noBackend(.zImage)
        #expect(EngineState.failed(error).title(for: model, availability: nil) == error.message)
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

    @Test("the File menu's stop item names what it stops, and rests on Stop Generating")
    func stopCommandNamesWhatItStops() {
        let downloading = EngineState.downloading(
            DownloadProgressEvent(completedFiles: 0, totalFiles: 1, fraction: 0))
        #expect(downloading.stopCommandTitle == "Cancel Download")
        let building = EngineState.building(
            BuildProgressEvent(component: "vae", completedComponents: 0, totalComponents: 2, fraction: 0))
        #expect(building.stopCommandTitle == "Stop Building")
        #expect(EngineState.checkingModel.stopCommandTitle == "Stop Loading")
        #expect(EngineState.loading(.preparing).stopCommandTitle == "Stop Loading")
        #expect(EngineState.warmingUp.stopCommandTitle == "Stop Loading")
        let upscaling = EngineState.upscaling(UpscaleProgressEvent(completedTiles: 0, totalTiles: 4))
        #expect(upscaling.stopCommandTitle == "Stop Upscaling")
        let generating = EngineState.generating(GenerationProgressEvent(phase: .preparing, fraction: 0))
        #expect(generating.stopCommandTitle == "Stop Generating")
        #expect(EngineState.cancelling.stopCommandTitle == "Stop Generating")
        #expect(EngineState.ready.stopCommandTitle == "Stop Generating")
        #expect(EngineState.idle.stopCommandTitle == "Stop Generating")
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
