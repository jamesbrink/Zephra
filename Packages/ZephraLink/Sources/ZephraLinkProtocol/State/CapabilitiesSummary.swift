import ZephraCore

/// What a model will accept, in a form that can be sent.
///
/// `ModelCapabilities` is not `Codable` and should not become so: it is a value the catalog
/// builds and nothing writes to disk. This carries its stored facts and nothing else — every
/// one of them, so `capabilities` reconstructs the real type and the phone runs the Mac's own
/// `clamp` rather than a second copy of the rules that could drift from it.
public struct CapabilitiesSummary: Codable, Hashable, Sendable {
    /// Both dimensions must be a multiple of this many pixels.
    public var sizeAlignment: Int
    /// Sizes worth offering as one-tap choices, in order.
    public var sizePresets: [ImageSize]
    /// The smallest and largest either dimension may take.
    public var sizeBounds: ClosedRange<Int>
    /// The size to start from.
    public var defaultSize: ImageSize
    /// The fewest and most denoising steps the model tolerates.
    public var stepBounds: ClosedRange<Int>
    /// The step count that balances speed and quality.
    public var defaultSteps: Int
    /// The range of guidance the model responds to; a single point means it has none.
    public var guidanceBounds: ClosedRange<Double>
    /// The guidance to start from.
    public var defaultGuidance: Double
    /// Whether a negative prompt changes the result.
    public var supportsNegativePrompt: Bool
    /// Whether a fixed seed reproduces an earlier image.
    public var supportsSeed: Bool
    /// Whether a picture can be handed in.
    public var supportsReferenceImage: Bool
    /// How many pictures the model reads; a single point at 1 means one, and is what a Mac
    /// that never mentioned it meant.
    public var referenceImageCount: ClosedRange<Int>
    /// Whether the model reads a picture's transparency rather than having it composited over
    /// white; false is what a Mac that never mentioned it meant, since no model did.
    public var readsTransparentReferences: Bool
    /// How far from that picture a run may start; a single point at 1 means it does not apply.
    public var referenceStrengthBounds: ClosedRange<Double>
    /// The strength to start from.
    public var defaultReferenceStrength: Double
    /// How many frames a generation may have; a single point at 1 means pictures.
    public var frameBounds: ClosedRange<Int>
    /// The frame count to start from.
    public var defaultFrames: Int
    /// Legal frame counts are `1 + k * frameAlignment`.
    public var frameAlignment: Int
    /// Frames per second the clips play at.
    public var frameRate: Double
    /// How many of a clip's last frames this model can hold to carry it on.
    public var continuationFrames: ClosedRange<Int>
    /// How many to hold when nothing else is said.
    public var defaultContinuationFrames: Int
    /// Whether the model makes sound beside its frames.
    public var producesAudio: Bool
}
