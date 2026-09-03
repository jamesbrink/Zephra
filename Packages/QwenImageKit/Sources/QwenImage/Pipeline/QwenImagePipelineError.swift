import Foundation

/// What can go wrong running the pipeline.
public enum QwenImagePipelineError: Error, LocalizedError, Equatable {
    /// A generation was asked for before any weights were loaded.
    case notLoaded
    /// The requested size is not a whole number of patches.
    case unalignedSize(width: Int, height: Int, alignment: Int)
    /// The decoded image could not be turned into PNG bytes.
    case encodingFailed
    /// A reference image was named that nothing could open.
    case referenceUnreadable(URL)

    public var errorDescription: String? {
        switch self {
        case .notLoaded:
            "No model is loaded."
        case .unalignedSize(let width, let height, let alignment):
            "\(width)x\(height) is not a multiple of \(alignment)."
        case .encodingFailed:
            "The image could not be encoded."
        case .referenceUnreadable(let url):
            "Could not read the reference image at \(url.path(percentEncoded: false))."
        }
    }
}
