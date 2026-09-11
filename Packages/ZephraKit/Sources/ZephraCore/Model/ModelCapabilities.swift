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
    /// How far from that picture a generation may start, on models that begin from a noised
    /// copy of it.
    ///
    /// A single point at 1 means strength does not apply, the way `guidanceBounds` of `0...0`
    /// means guidance does not — which is the honest answer for a model that conditions on the
    /// picture directly rather than starting from it. The interface reads the range: a
    /// degenerate one hides the control instead of offering a slider that does nothing.
    public let referenceStrengthBounds: ClosedRange<Double>
    /// The strength to start from, which should keep composition while redrawing detail.
    public let defaultReferenceStrength: Double
    /// How many frames a generation may have, on a model that makes clips.
    ///
    /// A single point at 1 means the model makes pictures, by the same rule as
    /// `referenceStrengthBounds`: the interface reads the range and draws no duration control
    /// over a single value. A video model's bounds are both of the form `1 + k * frameAlignment`.
    public let frameBounds: ClosedRange<Int>
    /// The frame count to start from on a model that makes clips; 1 on one that does not.
    public let defaultFrames: Int
    /// Legal frame counts are `1 + k * frameAlignment`: a video autoencoder compresses time by
    /// this factor and keeps the first frame, so 8 means 1, 9, 17, 25 and so on.
    public let frameAlignment: Int
    /// Frames per second the model was trained to make, which is what its clips play at.
    public let frameRate: Double
    /// How many of a finished clip's last frames the model can hold at the head of a new one,
    /// to carry the clip on: `0...0` on a model that cannot continue a clip, by the rule the
    /// other degenerate ranges follow. A family that holds one latent frame declares `1...1`;
    /// one that holds a run of them declares a range on its own ladder, `1 + k * frameAlignment`.
    public let continuationFrames: ClosedRange<Int>
    /// How many of those frames to hold when nothing else is said.
    public let defaultContinuationFrames: Int

    /// Creates a capability set describing one model's accepted inputs.
    ///
    /// The reference parameters carry defaults — no reference, and a strength that does
    /// nothing — so a descriptor written before either existed still compiles and still means
    /// what it meant. Everything else is spelled out at every site on purpose.
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
        referenceStrengthBounds: ClosedRange<Double> = 1...1,
        defaultReferenceStrength: Double = 1,
        frameBounds: ClosedRange<Int> = 1...1,
        defaultFrames: Int = 1,
        frameAlignment: Int = 8,
        frameRate: Double = 24,
        continuationFrames: ClosedRange<Int> = 0...0,
        defaultContinuationFrames: Int = 0
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
        self.referenceStrengthBounds = referenceStrengthBounds
        self.defaultReferenceStrength = defaultReferenceStrength
        self.frameBounds = frameBounds
        self.defaultFrames = defaultFrames
        self.frameAlignment = frameAlignment
        self.frameRate = frameRate
        self.continuationFrames = continuationFrames
        self.defaultContinuationFrames = defaultContinuationFrames
    }

    /// Whether guidance is a choice on this model. A distilled model declares a single legal
    /// value, and a slider over a single value is not a slider: SwiftUI stops the app rather
    /// than draw one, so every control reads this before it reads the bounds.
    public var adjustsGuidance: Bool { guidanceBounds.lowerBound < guidanceBounds.upperBound }

    /// Whether the step count is a choice on this model, by the same rule: a checkpoint
    /// distilled to a fixed ladder of sigmas, as LTX-2.5's is, declares one legal count.
    public var adjustsSteps: Bool { stepBounds.lowerBound < stepBounds.upperBound }

    /// Whether the reference strength is a choice on this model, by the same rule.
    public var adjustsReferenceStrength: Bool {
        referenceStrengthBounds.lowerBound < referenceStrengthBounds.upperBound
    }

    /// Whether the clip's length is a choice on this model, by the same rule.
    public var adjustsFrames: Bool { frameBounds.lowerBound < frameBounds.upperBound }

    /// Whether this model makes clips rather than pictures.
    public var producesVideo: Bool { frameBounds.upperBound > 1 }

    /// Whether this model can carry a finished clip on from its last frames.
    public var supportsContinuation: Bool { continuationFrames.upperBound > 0 }
}
