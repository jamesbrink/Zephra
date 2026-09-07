import Foundation
import Testing
import ZephraCore

@testable import Zephra
@testable import ZephraEngine

/// Why "Use as Reference" or "Animate" is disabled, when it is.
@Suite("why an action button is disabled")
struct ActionAvailabilityTests {
    /// Every model the catalog ships reads a picture now, so the model that does not has to be
    /// built rather than borrowed, as `ReferenceImageTests` does.
    private static let textOnly = ModelCapabilities(
        sizeAlignment: 64,
        sizePresets: [ImageSize(width: 1024, height: 1024)],
        sizeBounds: 512...1024,
        defaultSize: ImageSize(width: 1024, height: 1024),
        stepBounds: 1...9,
        defaultSteps: 9,
        guidanceBounds: 0...0,
        defaultGuidance: 0,
        supportsNegativePrompt: false,
        supportsSeed: true,
        supportsReferenceImage: false
    )

    @Test("Use as Reference names the model as the reason, or says nothing once it is live")
    func referenceReason() {
        #expect(
            ActionAvailability.referenceDisabledReason(capabilities: Self.textOnly)
                == "This model does not read a picture")
        for model in ModelCatalog.all {
            #expect(
                ActionAvailability.referenceDisabledReason(capabilities: model.capabilities) == "",
                "\(model.id) reads a picture")
        }
    }

    @Test("a picture always has a source; a clip has one once it is on disk or in memory")
    func hasAnimatableSource() {
        let picture = PreviewImages.sample()
        #expect(ActionAvailability.hasAnimatableSource(picture))

        let unsavedClip = GeneratedImage(
            pngData: picture.pngData,
            settings: GenerationSettings(
                prompt: "", size: picture.settings.size, steps: 1, guidance: 0, seed: 1, frames: 49),
            modelID: picture.modelID,
            duration: .seconds(1))
        #expect(unsavedClip.isVideo)
        #expect(!ActionAvailability.hasAnimatableSource(unsavedClip), "no file and no video in memory")

        let clipWithBytes = GeneratedImage(
            pngData: picture.pngData,
            settings: unsavedClip.settings,
            modelID: picture.modelID,
            duration: .seconds(1),
            video: GeneratedVideo(poster: picture.pngData, mp4: Data([0]), frameCount: 49, frameRate: 24))
        #expect(ActionAvailability.hasAnimatableSource(clipWithBytes), "the clip is still in memory")
    }

    @Test("Animate asks the store to wait while a folder change is in progress")
    func animateWaitsDuringAFolderChange() {
        let store = GenerationStore.preview(state: .ready)
        store.imageDirectoryProgress = "Moving images"
        #expect(
            ActionAvailability.animateDisabledReason(hasSource: true, store: store)
                == "Wait for the current work to finish")
    }

    @Test("Animate names the missing clip when the model would take it, but nothing has landed")
    func animateNamesTheMissingClip() {
        let store = GenerationStore.preview(state: .ready)
        #expect(
            ActionAvailability.animateDisabledReason(hasSource: false, store: store)
                == "This clip has not finished saving yet")
    }

    @Test("Animate says nothing once the store takes work and the clip has a source")
    func animateIsLive() {
        let store = GenerationStore.preview(state: .ready)
        #expect(ActionAvailability.animateDisabledReason(hasSource: true, store: store) == "")
    }
}
