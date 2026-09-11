import Foundation
import Testing
import ZephraCore
import ZephraLinkProtocol

@testable import ZephraMobile

/// The phone's capsule as a value: what it takes from the Mac, and what it asks the Mac for.
///
/// The point of every one of these is that the phone runs the Mac's own rules. A request that
/// left here holding something the model cannot run would be a request the Mac quietly
/// rewrites, and the person would be looking at settings that are not what ran.
@MainActor
@Suite("The draft takes the Mac's defaults and asks for what the Mac can run")
struct PromptDraftTests {
    /// A picture model that reads a reference and starts from a noised copy of it.
    private func pictureModel(reference: Bool = true) -> ModelSummary {
        ModelSummary(
            id: "test-picture", displayName: "Test", variantName: "4-bit", familyID: "test",
            capabilities: CapabilitiesSummary(
                ModelCapabilities(
                    sizeAlignment: 64,
                    sizePresets: [ImageSize(width: 1024, height: 1024)],
                    sizeBounds: 256...2048,
                    defaultSize: ImageSize(width: 1024, height: 1024),
                    stepBounds: 1...20, defaultSteps: 9,
                    guidanceBounds: 0...0, defaultGuidance: 0,
                    supportsNegativePrompt: false, supportsSeed: true,
                    supportsReferenceImage: reference,
                    referenceStrengthBounds: reference ? 0.1...0.9 : 1...1,
                    defaultReferenceStrength: reference ? 0.6 : 1)))
    }

    /// A clip model, which is the one kind whose size follows the picture.
    private func clipModel() -> ModelSummary {
        ModelSummary(
            id: "test-clip", displayName: "Test Clips", variantName: nil, familyID: "test",
            capabilities: CapabilitiesSummary(
                ModelCapabilities(
                    sizeAlignment: 32,
                    sizePresets: [ImageSize(width: 704, height: 704)],
                    sizeBounds: 256...1280,
                    defaultSize: ImageSize(width: 704, height: 704),
                    stepBounds: 3...3, defaultSteps: 3,
                    guidanceBounds: 0...0, defaultGuidance: 0,
                    supportsNegativePrompt: false, supportsSeed: true,
                    supportsReferenceImage: true,
                    frameBounds: 5...121, defaultFrames: 49, frameAlignment: 4,
                    continuationFrames: 1...9, defaultContinuationFrames: 5)))
    }

    private func snapshot(model: ModelSummary) -> StateSnapshot {
        StateSnapshot(
            hostName: "halcyon", model: model, models: [model],
            engine: EngineStateDTO(kind: .ready), queue: [], running: nil, history: [],
            availability: [:], downloads: [], today: [], libraryCount: 0, acceptsWork: true)
    }

    /// A picture of a known shape, without going through ImageIO.
    private func picture(width: Int, height: Int) -> ReferencePicture {
        ReferencePicture(data: Data([1, 2, 3]), size: ImageSize(width: width, height: height))
    }

    @Test("The first snapshot seeds the model and its defaults")
    func adoptSeedsTheModel() {
        let draft = PromptDraft()
        draft.adopt(snapshot(model: pictureModel()))
        #expect(draft.modelID == "test-picture")
        #expect(draft.settings.size == ImageSize(width: 1024, height: 1024))
        #expect(draft.settings.steps == 9)
        #expect(draft.settings.referenceStrength == 0.6)
    }

    @Test("A later snapshot never lands on a prompt somebody is typing")
    func adoptHappensOnce() {
        let draft = PromptDraft()
        draft.adopt(snapshot(model: pictureModel()))
        draft.settings.prompt = "a red bicycle"
        draft.settings.steps = 4
        draft.adopt(snapshot(model: clipModel()))
        #expect(draft.settings.prompt == "a red bicycle")
        #expect(draft.settings.steps == 4)
        #expect(draft.modelID == "test-picture")
    }

    @Test("The request is clamped to what the model can run")
    func requestIsClamped() {
        let draft = PromptDraft()
        let model = pictureModel()
        draft.adopt(snapshot(model: model))
        draft.settings.prompt = "a red bicycle"
        draft.settings.size = ImageSize(width: 1000, height: 1000)
        draft.settings.steps = 900
        let request = draft.request(clampedBy: model.capabilities)
        #expect(request.settings.size == ImageSize(width: 1024, height: 1024))
        #expect(request.settings.steps == 20)
        #expect(request.modelID == "test-picture")
    }

    @Test("A clip longer than one pass crosses whole, for the Mac to plan as a chain")
    func chainedLengthSurvivesTheClamp() {
        let draft = PromptDraft()
        let model = clipModel()
        draft.adopt(snapshot(model: model))
        draft.settings.prompt = "a long ride"
        draft.settings.frames = 349
        // `clamp` alone bounds a length at one pass, since no backend runs more; the Mac plans
        // the chain from the length it is handed, so the request must carry the whole clip.
        #expect(model.capabilities.capabilities.clamp(draft.settings).frames == 121)
        #expect(draft.request(clampedBy: model.capabilities).settings.frames == 349)
        // Past four passes it comes back to what four make, not to one.
        draft.settings.frames = 10_000
        #expect(draft.request(clampedBy: model.capabilities).settings.frames == 121 + 3 * 116)
    }

    @Test("The lengths offered are the Mac's, chained ones included")
    func lengthsAreTheMacs() {
        let capabilities = clipModel().capabilities.capabilities
        let choices = ClipLength.choices(capabilities)
        #expect(choices.contains { $0 > capabilities.frameBounds.upperBound })
        for frames in choices {
            #expect(ChainPlan.frames(frames, capabilities: capabilities) == frames)
        }
    }

    @Test("A model that reads no picture is not sent one")
    func referenceIsDroppedWhereItMeansNothing() {
        let draft = PromptDraft()
        let model = pictureModel(reference: false)
        draft.adopt(snapshot(model: model))
        draft.adopt(
            picture(width: 800, height: 600), origin: "a.png",
            fitting: model.capabilities.capabilities)
        let request = draft.request(clampedBy: model.capabilities)
        #expect(draft.reference != nil)
        #expect(request.settings.referenceOrigin == nil)
        #expect(draft.reference(allowedBy: model.capabilities) == nil)
    }

    @Test("A picture in the well crosses beside a request that can read one")
    func referenceCrossesWhereItIsRead() {
        let draft = PromptDraft()
        let model = pictureModel()
        draft.adopt(snapshot(model: model))
        draft.adopt(
            picture(width: 800, height: 600), origin: "a.png",
            fitting: model.capabilities.capabilities)
        #expect(draft.reference(allowedBy: model.capabilities) != nil)
        #expect(draft.request(clampedBy: model.capabilities).settings.referenceOrigin == "a.png")
    }

    @Test("On a clip model the size becomes the picture's own shape")
    func sizeFollowsThePictureOnAClipModel() {
        let draft = PromptDraft()
        let model = clipModel()
        draft.adopt(snapshot(model: model))
        let budget = draft.settings.size.pixelCount
        draft.adopt(
            picture(width: 1600, height: 900), origin: nil,
            fitting: model.capabilities.capabilities)
        #expect(draft.settings.size.width > draft.settings.size.height)
        #expect(draft.settings.size.width % 32 == 0)
        #expect(abs(draft.settings.size.pixelCount - budget) < budget / 4)
    }

    @Test("On a picture model the size is left alone")
    func sizeStaysPutOnAPictureModel() {
        let draft = PromptDraft()
        let model = pictureModel()
        draft.adopt(snapshot(model: model))
        draft.adopt(
            picture(width: 1600, height: 900), origin: nil,
            fitting: model.capabilities.capabilities)
        #expect(draft.settings.size == ImageSize(width: 1024, height: 1024))
    }

    @Test("Clearing the well takes the picture's provenance with it")
    func clearingTakesTheOrigin() {
        let draft = PromptDraft()
        let model = pictureModel()
        draft.adopt(snapshot(model: model))
        draft.adopt(
            picture(width: 800, height: 600), origin: "a.png",
            fitting: model.capabilities.capabilities)
        draft.clearReference()
        #expect(draft.reference == nil)
        #expect(draft.referenceSize == nil)
        #expect(draft.settings.referenceOrigin == nil)
    }

    @Test("Choosing another model puts the schedule on that model's ladder")
    func choosingAModelTakesItsSchedule() {
        let draft = PromptDraft()
        draft.adopt(snapshot(model: pictureModel()))
        draft.settings.prompt = "a red bicycle"
        draft.choose(clipModel())
        #expect(draft.modelID == "test-clip")
        #expect(draft.settings.steps == 3)
        #expect(draft.settings.frames == 49)
        #expect(draft.settings.prompt == "a red bicycle")
    }
}
