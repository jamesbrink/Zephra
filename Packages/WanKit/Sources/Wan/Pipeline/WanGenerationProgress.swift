import Foundation

/// Where a load or a generation has got to, reported as each stage is entered.
public struct WanGenerationProgress: Hashable, Sendable {
    /// What the pipeline is doing.
    public enum Stage: Hashable, Sendable {
        case loading
        case encodingPrompt
        case denoising(step: Int, of: Int)
        case decoding
    }

    /// The stage just entered.
    public let stage: Stage

    public init(stage: Stage) {
        self.stage = stage
    }
}
