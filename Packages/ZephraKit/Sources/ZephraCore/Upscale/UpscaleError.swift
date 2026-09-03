import Foundation

/// What can go wrong in an upscale, phrased so the message can be shown to the user as-is.
///
/// Its own type rather than more cases on `BackendError`, which is about a model family's
/// download, load, and generate life cycle. An upscaler has none of that.
public enum UpscaleError: Error, Sendable, Hashable, LocalizedError {
    /// This build carries no upscaler, or its weights could not be found.
    case weightsMissing(String)
    /// The network ran but did not produce a picture.
    case failed(String)
    /// The work was cancelled before it finished.
    case cancelled

    /// A short, plain-language explanation.
    public var errorDescription: String? {
        switch self {
        case let .weightsMissing(reason):
            "The upscaler isn't available: \(reason)"
        case let .failed(reason):
            "The image couldn't be upscaled. \(reason)"
        case .cancelled:
            "Upscaling was cancelled."
        }
    }
}
