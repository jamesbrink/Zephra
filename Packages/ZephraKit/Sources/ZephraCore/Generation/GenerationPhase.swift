/// Where a generation has got to, so the interface can say more than "working".
public enum GenerationPhase: Hashable, Sendable {
    /// Setting up before any compute starts.
    case preparing
    /// Turning the prompt into embeddings.
    case encodingText
    /// Running the diffusion loop, at `step` of `of` total steps.
    case denoising(step: Int, of: Int)
    /// Turning latents into pixels.
    case decoding
    /// Writing the finished image to disk.
    case saving
}
