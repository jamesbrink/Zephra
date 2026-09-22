import Foundation

/// What the pipeline can refuse to do, or fail at, once the configuration has been read.
public enum QwenImage21PipelineError: Error, LocalizedError, Equatable {
    /// `generate` was called before `loadModel`.
    case notLoaded
    /// The requested size is not a multiple of the latent grid.
    case unalignedSize(width: Int, height: Int, alignment: Int)
    /// A reference picture's bytes could not be read as a picture, or could not be resampled.
    case unreadableReference
    /// Injected noise whose shape is not the one this request's latent grid asks for. Only a
    /// parity harness hands noise in, and a shape that did not fit would otherwise broadcast
    /// into something the loop would happily denoise.
    case noiseDoesNotMatchLatent(given: [Int], expected: [Int])

    public var errorDescription: String? {
        switch self {
        case .notLoaded:
            "No model is loaded."
        case .unalignedSize(let width, let height, let alignment):
            "\(width)x\(height) is not a multiple of \(alignment) on both sides."
        case .unreadableReference:
            "A reference picture could not be read."
        case .noiseDoesNotMatchLatent(let given, let expected):
            "Noise of \(given) cannot stand in for a latent of \(expected)."
        }
    }
}
