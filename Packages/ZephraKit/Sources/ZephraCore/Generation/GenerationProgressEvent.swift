/// One progress update from a running generation.
public struct GenerationProgressEvent: Hashable, Sendable {
    /// What the backend is doing right now.
    public let phase: GenerationPhase
    /// Overall completion from 0 to 1, across all phases.
    public let fraction: Double
    /// Measured pace of the diffusion loop, absent until at least one step has finished.
    public let secondsPerStep: Double?

    /// Creates a progress update.
    public init(phase: GenerationPhase, fraction: Double, secondsPerStep: Double? = nil) {
        self.phase = phase
        self.fraction = fraction
        self.secondsPerStep = secondsPerStep
    }

    /// A countdown for the diffusion loop, which is the only phase whose pace is predictable.
    public var estimatedSecondsRemaining: Double? {
        guard case let .denoising(step, total) = phase, let secondsPerStep else { return nil }
        return Double(max(0, total - step)) * secondsPerStep
    }
}
