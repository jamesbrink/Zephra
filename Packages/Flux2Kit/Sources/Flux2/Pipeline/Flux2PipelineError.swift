import Foundation

/// What the pipeline can refuse to do, or fail at, once the configuration has been read.
public enum Flux2PipelineError: Error, LocalizedError, Equatable {
    /// `generate` was called before `loadModel`.
    case notLoaded
    /// The requested size is not a multiple of the latent grid.
    case unalignedSize(width: Int, height: Int, alignment: Int)
    /// The decoded image could not be turned into PNG bytes.
    case encodingFailed
    /// The reference image's bytes could not be read as a picture.
    case unreadableReference

    public var errorDescription: String? {
        switch self {
        case .notLoaded:
            "No model is loaded."
        case .unalignedSize(let width, let height, let alignment):
            "\(width)x\(height) is not a multiple of \(alignment) on both sides."
        case .encodingFailed:
            "The image could not be encoded as PNG."
        case .unreadableReference:
            "The reference image could not be read."
        }
    }
}
