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
    /// A picture to start the denoising from, on models that can encode one.
    ///
    /// Optional, and optional in the encoded form too: Swift's synthesised decoding reads an
    /// optional property with `decodeIfPresent`, so settings written before references existed
    /// still decode, with no reference.
    public var reference: ReferenceImage?

    /// Creates a settings value from explicit choices.
    public init(
        prompt: String,
        negativePrompt: String? = nil,
        size: ImageSize,
        steps: Int,
        guidance: Double,
        seed: UInt64,
        reference: ReferenceImage? = nil
    ) {
        self.prompt = prompt
        self.negativePrompt = negativePrompt
        self.size = size
        self.steps = steps
        self.guidance = guidance
        self.seed = seed
        self.reference = reference
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
    /// 1024 pixels whoever draws them.
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
