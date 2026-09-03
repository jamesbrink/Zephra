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
    /// default of 1 is the value that changes nothing. Optional in the *encoded* form, though:
    /// Swift's synthesised decoding reads a missing key into the initializer's default, so
    /// settings written before strength existed still decode.
    public var referenceStrength: Double

    /// Creates a settings value from explicit choices.
    public init(
        prompt: String,
        negativePrompt: String? = nil,
        size: ImageSize,
        steps: Int,
        guidance: Double,
        seed: UInt64,
        referenceImage: Data? = nil,
        referenceStrength: Double = 1
    ) {
        self.prompt = prompt
        self.negativePrompt = negativePrompt
        self.size = size
        self.steps = steps
        self.guidance = guidance
        self.seed = seed
        self.referenceImage = referenceImage
        self.referenceStrength = referenceStrength
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
            seed: .random(in: .min ... .max)
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
