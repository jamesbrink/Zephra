import ZephraCore

/// A failure the engine could not recover from on its own, phrased for the person using the app.
public enum EngineError: Error, Hashable, Sendable {
    /// The backend reported a problem while downloading, loading, or generating.
    case backend(BackendError)
    /// The image was generated but could not be written to disk.
    case saveFailed(String)
    /// No backend is registered for the model's backend identifier.
    case noBackend(BackendID)

    /// What went wrong and, where possible, what to do about it.
    public var message: String {
        switch self {
        case .backend(let error):
            return error.errorDescription ?? "Something went wrong in the image engine."
        case .saveFailed(let reason):
            return "The image was generated but couldn't be saved. \(reason)"
        case .noBackend(let id):
            return "No engine is available for \(id.rawValue). Choose a different model."
        }
    }
}
