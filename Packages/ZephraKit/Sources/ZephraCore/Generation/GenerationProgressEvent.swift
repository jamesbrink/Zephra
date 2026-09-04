/// One progress update from a running generation.
public struct GenerationProgressEvent: Hashable, Sendable {
    /// What the backend is doing right now.
    public let phase: GenerationPhase
    /// Overall completion from 0 to 1, across all phases.
    public let fraction: Double
    /// Measured pace of the diffusion loop, absent until at least one step has finished.
    public let secondsPerStep: Double?
    /// The latent as it stood at this step, decoded small, on the few updates that carry one.
    /// A backend sends frames far more rarely than steps: a preview is a whole pass through an
    /// autoencoder, so it is throttled to something a person can watch.
    public let preview: GenerationPreview?

    /// Creates a progress update.
    public init(
        phase: GenerationPhase,
        fraction: Double,
        secondsPerStep: Double? = nil,
        preview: GenerationPreview? = nil
    ) {
        self.phase = phase
        self.fraction = fraction
        self.secondsPerStep = secondsPerStep
        self.preview = preview
    }

    /// A countdown for the diffusion loop, which is the only phase whose pace is predictable.
    public var estimatedSecondsRemaining: Double? {
        guard case let .denoising(step, total) = phase, let secondsPerStep else { return nil }
        return Double(max(0, total - step)) * secondsPerStep
    }

    /// Equality over the progress and not over the picture.
    ///
    /// This type is embedded in `EngineState`, which is `Hashable` and compared on every
    /// transition, so both halves of the conformance run on the hot path of a generation. A
    /// frame is a quarter of a megabyte of pixels; comparing or hashing it would cost more than
    /// everything else the engine does per step, to answer a question no caller asks. Two
    /// updates that agree on the step and the pace are the same *progress* whether or not a
    /// frame came with one of them, and the store publishes the frame separately anyway.
    public static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.phase == rhs.phase && lhs.fraction == rhs.fraction
            && lhs.secondsPerStep == rhs.secondsPerStep
    }

    /// Hashes the same three fields `==` compares, and for the same reason.
    public func hash(into hasher: inout Hasher) {
        hasher.combine(phase)
        hasher.combine(fraction)
        hasher.combine(secondsPerStep)
    }
}
