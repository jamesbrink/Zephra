/// What a model will accept, so the interface can offer only settings that will actually run.
public struct ModelCapabilities: Hashable, Sendable {
    /// Both dimensions must be a multiple of this many pixels.
    public let sizeAlignment: Int
    /// Sizes worth offering as one-tap choices, in the order they should be shown.
    public let sizePresets: [ImageSize]
    /// The smallest and largest value either dimension may take.
    public let sizeBounds: ClosedRange<Int>
    /// The size to start from when nothing else is known.
    public let defaultSize: ImageSize
    /// The fewest and most denoising steps the model tolerates.
    public let stepBounds: ClosedRange<Int>
    /// The step count that balances speed and quality for this model.
    public let defaultSteps: Int
    /// The range of classifier-free guidance the model responds to.
    public let guidanceBounds: ClosedRange<Double>
    /// The guidance value to start from.
    public let defaultGuidance: Double
    /// Whether a negative prompt changes the result at all.
    public let supportsNegativePrompt: Bool
    /// Whether a fixed seed reproduces an earlier image.
    public let supportsSeed: Bool
    /// Whether the model can start from a picture instead of from pure noise.
    ///
    /// This asks only whether the family has an image encoder Zephra can reach and a schedule
    /// that interpolates linearly, which is what SDEdit needs. It is not a claim about edit
    /// conditioning: a model that takes a reference image as a *prompt* is a different model,
    /// not this flag turned on.
    public let supportsReferenceImage: Bool
    /// How far a reference may be taken from, when one is supported.
    ///
    /// Neither end is offered: 1 is text-to-image with extra steps, and 0 hands the picture
    /// back unchanged.
    public let referenceStrengthBounds: ClosedRange<Double>
    /// The strength to start from, which should keep composition while redrawing detail.
    public let defaultReferenceStrength: Double

    /// Creates a capability set describing one model's accepted inputs.
    ///
    /// The reference-image parameters carry defaults — no reference, and the usual bounds — so
    /// that a descriptor written before references existed still compiles and still means what
    /// it meant. Everything else is spelled out at every site on purpose.
    public init(
        sizeAlignment: Int,
        sizePresets: [ImageSize],
        sizeBounds: ClosedRange<Int>,
        defaultSize: ImageSize,
        stepBounds: ClosedRange<Int>,
        defaultSteps: Int,
        guidanceBounds: ClosedRange<Double>,
        defaultGuidance: Double,
        supportsNegativePrompt: Bool,
        supportsSeed: Bool,
        supportsReferenceImage: Bool = false,
        referenceStrengthBounds: ClosedRange<Double> = 0.1...0.9,
        defaultReferenceStrength: Double = 0.6
    ) {
        self.supportsReferenceImage = supportsReferenceImage
        self.referenceStrengthBounds = referenceStrengthBounds
        self.defaultReferenceStrength = defaultReferenceStrength
        self.sizeAlignment = sizeAlignment
        self.sizePresets = sizePresets
        self.sizeBounds = sizeBounds
        self.defaultSize = defaultSize
        self.stepBounds = stepBounds
        self.defaultSteps = defaultSteps
        self.guidanceBounds = guidanceBounds
        self.defaultGuidance = defaultGuidance
        self.supportsNegativePrompt = supportsNegativePrompt
        self.supportsSeed = supportsSeed
    }

    /// Rewrites settings into the nearest form this model can run, rather than rejecting them.
    public func clamp(_ settings: GenerationSettings) -> GenerationSettings {
        var result = settings
        result.size = constrain(settings.size)
        result.steps = min(max(settings.steps, stepBounds.lowerBound), stepBounds.upperBound)
        result.guidance = min(
            max(settings.guidance, guidanceBounds.lowerBound),
            guidanceBounds.upperBound
        )
        if !supportsNegativePrompt {
            result.negativePrompt = nil
        }
        result.reference = constrain(settings.reference)
        return result
    }

    /// The reference this model will actually honour: none at all when it cannot encode one,
    /// and otherwise the same picture at a strength inside the bounds.
    private func constrain(_ reference: ReferenceImage?) -> ReferenceImage? {
        guard supportsReferenceImage, let reference else { return nil }
        let strength = min(
            max(reference.strength, referenceStrengthBounds.lowerBound),
            referenceStrengthBounds.upperBound
        )
        return reference.withStrength(strength)
    }

    private func constrain(_ size: ImageSize) -> ImageSize {
        let aligned = size.aligned(to: sizeAlignment)
        return ImageSize(width: bound(aligned.width), height: bound(aligned.height))
    }

    private func bound(_ value: Int) -> Int {
        if value < sizeBounds.lowerBound {
            let steps = (sizeBounds.lowerBound + sizeAlignment - 1) / sizeAlignment
            return steps * sizeAlignment
        }
        if value > sizeBounds.upperBound {
            return (sizeBounds.upperBound / sizeAlignment) * sizeAlignment
        }
        return value
    }
}
