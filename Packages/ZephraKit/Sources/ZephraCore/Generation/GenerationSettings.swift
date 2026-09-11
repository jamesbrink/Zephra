import Foundation

/// Everything the user chose for one generation, kept separate from the model that will run it.
public struct GenerationSettings: Hashable, Sendable, Codable {
    /// What the image should show.
    public var prompt: String
    /// What to steer away from, on models that read it.
    public var negativePrompt: String?
    /// The pixel dimensions to render.
    public var size: ImageSize
    /// How many denoising steps to run.
    public var steps: Int
    /// How strongly the prompt overrides the model's own priors.
    public var guidance: Double
    /// The noise seed, so an image can be reproduced exactly.
    public var seed: UInt64
    /// A picture to edit rather than start from noise, as PNG bytes, on models that read one.
    ///
    /// Bytes and not a file URL. A settings value is what the user chose, and it has to keep
    /// meaning that after the file is moved, after the app quits, and twenty minutes later when
    /// its queue entry finally runs. The interface caps the picture before it lands here, so a
    /// reference is a megabyte or two, the same order as the images history already holds.
    public var referenceImage: Data?
    /// How far from that picture to start, on models that begin from a noised copy of it.
    ///
    /// 1 discards the picture entirely and is the ordinary text-to-image path; smaller values
    /// keep more of it. A model that conditions on the picture *directly* — FLUX.2 klein
    /// attends to it as extra tokens and still walks the whole schedule from noise — ignores
    /// this, and says so with a `referenceStrengthBounds` of `1...1`.
    ///
    /// Not optional, because every generation has one whether or not its model reads it, and a
    /// default of 1 is the value that changes nothing. Optional in the *encoded* form, though,
    /// which is what `GenerationSettings+Codable.swift` is for: a synthesised `Decodable` throws
    /// on a missing key for a non-optional property — the memberwise initializer's default is
    /// not the decoder's — so reading a value written before strength existed takes a
    /// hand-written `init(from:)`.
    public var referenceStrength: Double
    /// The library file name the reference picture came out of, when it came from the library,
    /// and nil when it came from a file chooser or a drop.
    ///
    /// A name and not a path, for the reason the record it is written into is inside the PNG: a
    /// library that survives being moved to another Mac cannot hold absolute paths. It is
    /// provenance for the person looking at the result — "this started from that picture" —
    /// and nothing reads it to find the file except an interface offering to show it.
    public var referenceOrigin: String?
    /// How many frames to make, on models that make a clip; 1 is a picture.
    ///
    /// Not optional, for the same reason `referenceStrength` is not: every generation has a
    /// frame count whether or not its model reads one, and 1 is the value that changes
    /// nothing. `ModelCapabilities.frameBounds` says whether it applies, and `clamp` pins it
    /// to 1 for every model that makes pictures.
    public var frames: Int
    /// The end of a finished clip to carry on from, on models that continue one; nil for a
    /// clip made from nothing or from a picture.
    ///
    /// Optional, unlike `frames` and `referenceStrength`, because there is no value that
    /// changes nothing: a continuation is either there or it is not, the way a reference
    /// picture is. `ModelCapabilities.continuationFrames` says whether a model reads one, and
    /// `clamp` drops it for every model that cannot and trims it to what one can hold.
    public var continuation: ClipContinuation?

    /// Creates a settings value from explicit choices.
    public init(
        prompt: String,
        negativePrompt: String? = nil,
        size: ImageSize,
        steps: Int,
        guidance: Double,
        seed: UInt64,
        referenceImage: Data? = nil,
        referenceStrength: Double = 1,
        referenceOrigin: String? = nil,
        frames: Int = 1,
        continuation: ClipContinuation? = nil
    ) {
        self.prompt = prompt
        self.negativePrompt = negativePrompt
        self.size = size
        self.steps = steps
        self.guidance = guidance
        self.seed = seed
        self.referenceImage = referenceImage
        self.referenceStrength = referenceStrength
        self.referenceOrigin = referenceOrigin
        self.frames = frames
        self.continuation = continuation
    }

    /// The starting point for a model: an empty prompt, its own defaults, and a fresh seed.
    public static func defaults(for descriptor: ModelDescriptor) -> GenerationSettings {
        let capabilities = descriptor.capabilities
        return GenerationSettings(
            prompt: "",
            negativePrompt: nil,
            size: capabilities.defaultSize,
            steps: capabilities.defaultSteps,
            guidance: capabilities.defaultGuidance,
            seed: .random(in: .min ... .max),
            frames: capabilities.defaultFrames
        )
    }

    /// A copy on `descriptor`'s own denoising schedule, keeping everything a prompt is about.
    ///
    /// Steps and guidance do not mean the same thing to two families. Nine steps of Z-Image
    /// Turbo's schedule and nine of a four-step distillation are different requests, and a
    /// number that happens to be inside both models' bounds survives clamping while meaning
    /// something else on the other side of it. A size or a seed does carry over: 1024 pixels is
    /// 1024 pixels whoever draws them, and a picture handed in to edit is the same picture whoever
    /// edits it; clamping drops it where the new model cannot read one.
    public func onSchedule(of descriptor: ModelDescriptor) -> GenerationSettings {
        var copy = self
        copy.steps = descriptor.capabilities.defaultSteps
        copy.guidance = descriptor.capabilities.defaultGuidance
        // Strength is a schedule setting too: a share of the steps means nothing across a move
        // from nine steps to four, and on a model that conditions on the picture directly it
        // means nothing at all.
        copy.referenceStrength = descriptor.capabilities.defaultReferenceStrength
        // A clip's length is the model's to offer: a picture model has no frames to carry
        // over, and one video model's ladder of lengths is not another's.
        copy.frames = descriptor.capabilities.defaultFrames
        return copy
    }

    /// A copy that will produce a different image from the same prompt.
    public func withRandomSeed() -> GenerationSettings {
        var copy = self
        copy.seed = .random(in: .min ... .max)
        return copy
    }

    /// Whether there is enough here to start, which means a prompt that is not just whitespace.
    public var isReadyToGenerate: Bool {
        !prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}
