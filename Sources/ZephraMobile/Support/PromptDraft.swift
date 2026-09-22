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
///
/// The well is a **list** (`PromptDraft+ReferenceStrip`), because a model may read several
/// pictures in the order they were chosen. The three scalars below are computed over its first
/// picture, exactly as `GenerationSettings.referenceImage` is over `referenceImages`, so every
/// reader that only ever meant "the picture" is untouched by the strip existing.
@MainActor
@Observable
final class PromptDraft {
    /// Everything the person chose, in the Mac's own type, so `clamp` is the same code here.
    var settings: GenerationSettings
    /// The model the next press names, as a descriptor identifier.
    var modelID: String
    /// The pictures the next run starts from, in the order the model reads them, each at most
    /// 1024 pixels an edge (`ReferenceImageEncoder`) and each carrying the library name it came
    /// out of. Empty for a run from nothing.
    ///
    /// Held here rather than in `settings` because a `GenerationSettings` carries a picture only
    /// as part of a request, and the well holds one until a press composes that request.
    private(set) var references: [ReferencePicture] = []
    /// What the last adoption could not take, in one sentence, or nil when it took everything.
    private(set) var referenceNote: String?
    /// How many seeds one press is worth.
    var count: Int

    /// The first picture's bytes, which is what every reader that means "the picture" wants.
    /// Nil for an empty well and for a picture whose pixels were stripped for the wire.
    var reference: Data? {
        guard let first = references.first, first.hasPixels else { return nil }
        return first.data
    }
    /// The shape of the first picture, which the Size menu offers at every tier's cost.
    var referenceSize: ImageSize? { references.first?.size }
    /// The library file name the first picture came out of, when it came from the Mac's library.
    var referenceOrigin: String? { references.first?.origin }

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
    /// rewrites. The pictures ride along only long enough to be clamped: `GenerationRequest`
    /// strips them, because a picture crosses as a blob and is named there by its id. An older
    /// Mac's summary says `1...1`, so the clamp is what trims a strip to its first picture —
    /// one rule, stated by the Mac being spoken to rather than guessed at here.
    ///
    /// The length is the one exception, and `ChainPlan` is why. `clamp` bounds frames at one
    /// pass, because a request that reaches a backend must never be longer than it runs; a
    /// longer clip is a chain of passes, and `GenerationStore.enqueue` plans that chain from
    /// the length it is handed before it clamps the first pass. So a clamped length here would
    /// be a ten-second clip quietly cut to five. The whole length is put back after the clamp,
    /// bounded and snapped the way the chain will make it.
    func request(clampedBy summary: CapabilitiesSummary) -> GenerationRequest {
        var chosen = settings
        chosen.referenceImages = references
        let capabilities = summary.capabilities
        var clamped = capabilities.clamp(chosen)
        clamped.frames = ChainPlan.frames(chosen.frames, capabilities: capabilities)
        return GenerationRequest(modelID: modelID, count: count, settings: clamped)
    }

    /// A fresh seed, which is what the shuffle asks for.
    func randomizeSeed() {
        settings.seed = .random(in: .min ... .max)
    }

    /// The strip and its note together, which is the one write `PromptDraft+ReferenceStrip`
    /// makes: every change to the well is a new list and a new answer about what would not fit.
    func setReferences(_ pictures: [ReferencePicture], note: String? = nil) {
        references = pictures
        referenceNote = note
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
