import Foundation

/// What can go wrong in a backend, phrased so the message can be shown to the user as-is.
public enum BackendError: Error, Sendable, Hashable, LocalizedError {
    /// The requested model has no implementation or no weights on disk.
    case modelNotAvailable(String)
    /// The download did not finish. The string says why, in a sentence a person can act on,
    /// because "check your connection" is the wrong advice for a missing repository or a full disk.
    case downloadFailed(String)
    /// The weights are present but could not be read into memory.
    case loadFailed(String)
    /// Inference started but did not produce an image.
    case generationFailed(String)
    /// The settings cannot be run by this model.
    case invalidSettings(String)
    /// The work was cancelled before it finished.
    case cancelled

    /// A short, plain-language explanation, with a next step wherever there is one.
    public var errorDescription: String? {
        switch self {
        case let .modelNotAvailable(name):
            "\(name) isn't on this Mac. Choose another model from the menu."
        case let .downloadFailed(reason):
            "Couldn't download the model. \(reason)"
        case .loadFailed:
            "Couldn't load the model. Free up some memory and try again."
        case .generationFailed:
            "The image couldn't be generated. Try again, or lower the size or step count."
        case let .invalidSettings(reason):
            "These settings won't run: \(reason)"
        case .cancelled:
            "Generation was cancelled."
        }
    }
}
