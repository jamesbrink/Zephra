import Foundation
import Observation
import ZephraCore
import ZephraLinkProtocol

/// The phone's capsule, as a value: what the next press of Generate would ask the Mac for.
///
/// `GenerationStore`'s settings half, and only that half. The Mac owns the run — it clamps, it
/// queues, it decides what is possible — so nothing here is a fact about the Mac; it is a
/// request being composed. Everything that came over the link is read from `LinkClient`, and a
/// draft that held a copy of one would be a draft that could disagree with it.
///
/// Built once by the composition root and injected, so a prompt survives a walk to the library
/// and back the way the Mac's capsule survives a walk to another pane.
@MainActor
@Observable
final class PromptDraft {
    /// Everything the person chose, in the Mac's own type, so `clamp` is the same code here.
    var settings: GenerationSettings
    /// The model the next press names, as a descriptor identifier.
    var modelID: String
    /// The reference picture as PNG bytes, at most 1024 pixels an edge
    /// (`ReferenceImageEncoder`), or nil for a run from nothing.
    var reference: Data?
    /// How many seeds one press is worth.
    var count: Int
    /// The shape of the picture in the well, which the Size menu offers at every tier's cost.
    /// It moves with the picture and is nil whenever the well is empty.
    private(set) var referenceSize: ImageSize?
    /// The library file name the picture in the well came out of, when it came from the Mac's
    /// library. Held here beside the bytes rather than in `settings`, because a
    /// `GenerationSettings` carries an origin only as a fact about a picture it is holding, and
    /// the well's picture is held here until the press composes the request.
    private(set) var referenceOrigin: String?

    /// Whether a snapshot has already seeded this draft. The first one is the Mac saying which
    /// model is in force and what it defaults to; every one after it would overwrite a prompt
    /// somebody is in the middle of typing.
    @ObservationIgnored private var hasAdopted = false
    /// The last prompt this draft took from a run of the Mac's or sent it as one, which is how
    /// `follow` tells a draft nobody has touched from one somebody typed into
    /// (`PromptDraft+FollowingRun`). Set there and by `noteSubmitted`, nowhere else.
    @ObservationIgnored var followedPrompt: String?

    /// An empty draft, before any Mac has said what it can do.
    init() {
        settings = GenerationSettings(
            prompt: "", size: ImageSize(width: 1024, height: 1024), steps: 9, guidance: 0,
            seed: .random(in: .min ... .max))
        modelID = ""
        reference = nil
        count = 1
    }

    /// Seeds the model and its defaults from the Mac's state, the first time one arrives, and
    /// then follows the run the Mac is in the middle of, if there is one.
    ///
    /// The prompt is kept, since somebody may have typed one before the link came up, and so is
    /// the seed, which is this launch's and not the Mac's; `follow` has the same rule, so a run
    /// in flight replaces neither of them over something typed.
    func adopt(_ snapshot: StateSnapshot?) {
        guard !hasAdopted, let snapshot else { return }
        hasAdopted = true
        modelID = snapshot.model.id
        settings = Self.defaults(
            for: snapshot.model.capabilities, prompt: settings.prompt, seed: settings.seed)
        // Only initial defaults are adopted; external runs never replace a multi-host draft.
    }

    /// An explicit local choice must survive the first snapshot arriving later.
    func preserveChosenSettings() { hasAdopted = true }

    /// Names another model, putting the schedule settings on its own ladder the way
    /// `GenerationSettings.onSchedule(of:)` does: steps, guidance, strength and length mean
    /// different things to two families, and a number inside both models' bounds survives
    /// clamping while meaning something else on the other side of it. The prompt, the size and
    /// the seed carry over.
    func choose(_ model: ModelSummary) {
        modelID = model.id
        let capabilities = model.capabilities
        settings.steps = capabilities.defaultSteps
        settings.guidance = capabilities.defaultGuidance
        settings.referenceStrength = capabilities.defaultReferenceStrength
        settings.frames = capabilities.defaultFrames
    }

    /// The request this draft makes against the model the summary describes.
    ///
    /// Clamped through the real `ModelCapabilities` rebuilt from the wire form, so the phone
    /// asks for what the Mac would have allowed rather than for something the Mac then quietly
    /// rewrites. The picture rides along only long enough to be clamped: `GenerationRequest`
    /// strips it, because a picture crosses as a blob and is named there by its id.
    ///
    /// The length is the one exception, and `ChainPlan` is why. `clamp` bounds frames at one
    /// pass, because a request that reaches a backend must never be longer than it runs; a
    /// longer clip is a chain of passes, and `GenerationStore.enqueue` plans that chain from
    /// the length it is handed before it clamps the first pass. So a clamped length here would
    /// be a ten-second clip quietly cut to five. The whole length is put back after the clamp,
    /// bounded and snapped the way the chain will make it.
    func request(clampedBy summary: CapabilitiesSummary) -> GenerationRequest {
        var chosen = settings
        chosen.referenceImages = reference.map {
            [ReferencePicture(data: $0, origin: referenceOrigin, size: referenceSize)]
        } ?? []
        let capabilities = summary.capabilities
        var clamped = capabilities.clamp(chosen)
        clamped.frames = ChainPlan.frames(chosen.frames, capabilities: capabilities)
        return GenerationRequest(modelID: modelID, count: count, settings: clamped)
    }

    /// The picture to send beside that request, or nil where the model would not read one.
    func reference(allowedBy summary: CapabilitiesSummary) -> Data? {
        summary.supportsReferenceImage ? reference : nil
    }

    /// Takes a picture into the well, and lets the size follow it the way the Mac's
    /// `useAsReference` does: on a model that makes clips the frame becomes the picture's own
    /// shape at the pixel budget in force, since a clip is the picture moving; a model that
    /// makes pictures leaves the size alone.
    func adopt(
        _ picture: ReferencePicture, origin: String?, fitting capabilities: ModelCapabilities
    ) {
        reference = picture.data
        referenceSize = picture.size
        referenceOrigin = origin
        guard capabilities.producesVideo, let size = picture.size,
            let shape = capabilities.size(matchingAspectOf: size, budget: settings.size.pixelCount)
        else { return }
        settings.size = shape
    }

    /// Empties the well. Where the picture came from is a fact about the picture, so it goes
    /// with it rather than outliving it.
    func clearReference() {
        reference = nil
        referenceSize = nil
        referenceOrigin = nil
        settings.referenceImages = []
    }

    /// A fresh seed, which is what the shuffle asks for.
    func randomizeSeed() {
        settings.seed = .random(in: .min ... .max)
    }

    /// One model's starting settings.
    private static func defaults(
        for summary: CapabilitiesSummary, prompt: String, seed: UInt64
    ) -> GenerationSettings {
        GenerationSettings(
            prompt: prompt, size: summary.defaultSize, steps: summary.defaultSteps,
            guidance: summary.defaultGuidance, seed: seed,
            referenceStrength: summary.defaultReferenceStrength, frames: summary.defaultFrames)
    }
}
