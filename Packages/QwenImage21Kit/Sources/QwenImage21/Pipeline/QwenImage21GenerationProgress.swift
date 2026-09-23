/// Where the pipeline is, reported as it goes.
public struct QwenImage21GenerationProgress: Hashable, Sendable {
    /// The stages a load or a generation passes through.
    public enum Stage: Hashable, Sendable {
        /// Reading weights into memory.
        case loading
        /// Running the vision-language encoder over the prompt, and the tower over any
        /// reference pictures inside it.
        case encodingPrompt
        /// Running the autoencoder's encoder over the reference pictures.
        case encodingReferences
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
