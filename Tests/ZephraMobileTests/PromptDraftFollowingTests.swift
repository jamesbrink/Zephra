import Foundation
import Testing
import ZephraCore
import ZephraLinkProtocol

@testable import ZephraMobile

/// The capsule follows the Mac's run the way the Mac's own does, and never over something
/// typed here: the one fact the phone holds that the Mac did not say is the one it keeps.
@MainActor
@Suite("The draft follows the run the Mac is making, unless somebody is typing")
struct PromptDraftFollowingTests {
    private func model(_ id: String, steps: Int) -> ModelSummary {
        ModelSummary(
            id: id, displayName: id, variantName: nil, familyID: "test",
            capabilities: CapabilitiesSummary(
                ModelCapabilities(
                    sizeAlignment: 64,
                    sizePresets: [ImageSize(width: 1024, height: 1024)],
                    sizeBounds: 256...2048,
                    defaultSize: ImageSize(width: 1024, height: 1024),
                    stepBounds: 1...20, defaultSteps: steps,
                    guidanceBounds: 0...0, defaultGuidance: 0,
                    supportsNegativePrompt: false, supportsSeed: true,
                    supportsReferenceImage: true,
                    referenceStrengthBounds: 0.1...0.9, defaultReferenceStrength: 0.6)))
    }

    private var picture: ModelSummary { model("test-picture", steps: 9) }
    private var other: ModelSummary { model("test-other", steps: 4) }

    private func snapshot(running: QueuedEntry? = nil) -> StateSnapshot {
        StateSnapshot(
            hostName: "halcyon", model: picture, models: [picture, other],
            engine: EngineStateDTO(kind: running == nil ? .ready : .generating), queue: [],
            running: running, history: [], availability: [:], downloads: [], today: [],
            libraryCount: 0, acceptsWork: true)
    }

    /// One run of the Mac's, with a picture in its well that the row cannot carry.
    private func run(_ prompt: String, on model: ModelSummary? = nil, seed: UInt64 = 7) -> QueuedEntry {
        QueuedEntry(
            id: UUID(), batchID: UUID(), batchIndex: 0, modelID: (model ?? picture).id,
            settings: GenerationSettings(
                prompt: prompt, size: ImageSize(width: 768, height: 1024), steps: 12,
                guidance: 0, seed: seed, referenceImage: Data([1, 2, 3]),
                referenceStrength: 0.4, referenceOrigin: "source.png"))
    }

    @Test("Following a run fills the prompt and the rest of its settings")
    func followingFillsTheCapsule() {
        let draft = PromptDraft()
        draft.adopt(snapshot())
        draft.adopt(
            ReferencePicture(data: Data([9]), size: ImageSize(width: 800, height: 600)),
            origin: "mine.png", fitting: picture.capabilities.capabilities)
        draft.follow(run("a red bicycle"))
        #expect(draft.settings.prompt == "a red bicycle")
        #expect(draft.settings.size == ImageSize(width: 768, height: 1024))
        #expect(draft.settings.steps == 12)
        #expect(draft.settings.seed == 7)
        #expect(draft.settings.referenceStrength == 0.4)
        // The phone has no pixels for the Mac's well, but it knows what the picture was.
        #expect(draft.reference == nil)
        #expect(draft.referenceSize == nil)
        #expect(draft.settings.referenceImage == nil)
        #expect(draft.settings.referenceOrigin == "source.png")
    }

    @Test("A prompt somebody typed is never written over")
    func typedPromptIsKept() {
        let draft = PromptDraft()
        draft.adopt(snapshot())
        draft.settings.prompt = "my own idea"
        draft.settings.steps = 3
        draft.follow(run("a red bicycle"))
        #expect(draft.settings.prompt == "my own idea")
        #expect(draft.settings.steps == 3)
        #expect(draft.settings.referenceOrigin == nil)
    }

    @Test("A prompt the phone sent is followed, and a later run of the Mac's replaces it")
    func submittedPromptIsReplacedByTheNextRun() {
        let draft = PromptDraft()
        draft.adopt(snapshot())
        draft.settings.prompt = "a lighthouse"
        draft.noteSubmitted(draft.request(clampedBy: picture.capabilities))
        draft.follow(run("a lighthouse", seed: 99))
        #expect(draft.settings.prompt == "a lighthouse")
        #expect(draft.settings.seed == 99, "the phone's own run is followed, seed and all")
        draft.follow(nil)
        #expect(draft.settings.prompt == "a lighthouse", "a run ending changes nothing")
        draft.follow(run("a red bicycle"))
        #expect(draft.settings.prompt == "a red bicycle")
    }

    @Test("A run the phone did not send is followed only once, and a typed edit sticks")
    func editingAfterAFollowIsKept() {
        let draft = PromptDraft()
        draft.adopt(snapshot())
        draft.follow(run("a red bicycle"))
        draft.settings.prompt = "a red bicycle, at night"
        draft.follow(run("a lighthouse"))
        #expect(draft.settings.prompt == "a red bicycle, at night")
    }

    @Test("The first snapshot with a run in flight seeds the capsule from the run")
    func firstSnapshotSeedsFromTheRun() {
        let draft = PromptDraft()
        draft.adopt(snapshot(running: run("a red bicycle")))
        #expect(draft.settings.prompt == "a red bicycle")
        #expect(draft.settings.steps == 12)
        #expect(draft.settings.size == ImageSize(width: 768, height: 1024))
    }

    @Test("The first snapshot never lands a run on a prompt typed before the link came up")
    func firstSnapshotKeepsATypedPrompt() {
        let draft = PromptDraft()
        draft.settings.prompt = "typed offline"
        draft.adopt(snapshot(running: run("a red bicycle")))
        #expect(draft.settings.prompt == "typed offline")
        #expect(draft.settings.steps == 9, "the model's defaults, not the run's")
    }

    @Test("Following a run on another model puts the capsule on that model")
    func followingMovesTheModel() {
        let draft = PromptDraft()
        draft.adopt(snapshot())
        #expect(draft.modelID == "test-picture")
        draft.follow(run("a red bicycle", on: other))
        #expect(draft.modelID == "test-other")
        #expect(draft.settings.steps == 12, "the run's own settings, not the model's defaults")
    }
}
