import ZephraCore

/// A failure the engine could not recover from on its own, phrased for the person using the app.
public enum EngineError: Error, Hashable, Sendable {
    /// The backend reported a problem while downloading, loading, or generating.
    case backend(BackendError)
    /// No backend is registered for the model's backend identifier: a catalog entry names an
    /// engine the composition root never registered.
    case noBackend(BackendID)

    /// What went wrong and, where possible, what to do about it.
    public var message: String {
        switch self {
        case .backend(let error):
            return error.errorDescription ?? "Something went wrong in the image engine."
        case .noBackend(let id):
            return "No engine is available for \(id.rawValue). Choose a different model."
        }
    }
}
