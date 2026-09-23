/// The questions a view asks of a capability set before it draws a control: whether a setting
/// is a choice at all on this model, and what kind of thing the model makes. Each reads a
/// declared range, so a degenerate range is the one way a model says "not a choice".
extension ModelCapabilities {
    /// Whether guidance is a choice on this model. A distilled model declares a single legal
    /// value, and a slider over a single value is not a slider: SwiftUI stops the app rather
    /// than draw one, so every control reads this before it reads the bounds.
    public var adjustsGuidance: Bool { guidanceBounds.lowerBound < guidanceBounds.upperBound }

    /// Whether the step count is a choice on this model, by the same rule: a checkpoint
    /// distilled to a fixed ladder of sigmas, as LTX-2.5's is, declares one legal count.
    public var adjustsSteps: Bool { stepBounds.lowerBound < stepBounds.upperBound }

    /// Whether this model reads more than one picture, which is what a view reads to decide
    /// between a single well and a strip of them.
    public var acceptsSeveralReferences: Bool {
        supportsReferenceImage && referenceImageCount.upperBound > 1
    }

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
