/// Where the pipeline is, reported as it goes.
public struct Flux2GenerationProgress: Hashable, Sendable {
    /// The stages a load or a generation passes through.
    public enum Stage: Hashable, Sendable {
        /// Reading weights into memory.
        case loading
        /// Running the text encoder over the prompt.
        case encodingPrompt
        /// Running the autoencoder's encoder over the reference picture.
        case encodingReference
        /// One denoising step, zero-based, of the total.
        case denoising(step: Int, of: Int)
        /// Running the autoencoder's decoder over the finished latent.
        case decoding
    }

    /// The stage just entered.
    public let stage: Stage

    /// Creates a progress value.
    public init(stage: Stage) {
        self.stage = stage
    }
}
