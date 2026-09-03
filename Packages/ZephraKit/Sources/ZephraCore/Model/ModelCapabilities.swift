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
    /// Whether a picture can be handed in to be edited rather than started from noise.
    public let supportsReferenceImage: Bool

    /// Creates a capability set describing one model's accepted inputs.
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
        supportsReferenceImage: Bool = false
    ) {
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
        self.supportsReferenceImage = supportsReferenceImage
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
        if !supportsReferenceImage {
            result.referenceImage = nil
        }
        return result
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
