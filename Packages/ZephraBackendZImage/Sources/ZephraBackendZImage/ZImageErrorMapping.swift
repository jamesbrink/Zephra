import Foundation
import ZephraCore
import ZImage

/// Turns errors thrown by the vendored library into `BackendError` values whose messages are
/// safe to put in front of a person.
nonisolated enum ZImageErrorMapping {
    /// Classifies a model-resolution failure. A missing repository or a login wall means the
    /// weights are not obtainable at all, which is a different problem from a transfer that
    /// broke halfway.
    static func downloadError(
        _ error: ModelResolutionError,
        descriptor: ModelDescriptor
    ) -> BackendError {
        switch error {
        case .modelNotFound, .authorizationRequired:
            .modelNotAvailable(descriptor.fullName)
        case .networkUnavailable, .downloadFailed:
            .downloadFailed(message(error))
        }
    }

    /// The most specific description an error carries: `LocalizedError` text when the library
    /// wrote one, and the type's own description otherwise, since several of the pipeline's
    /// error cases have no message of their own.
    static func message(_ error: some Error) -> String {
        if let localized = (error as? any LocalizedError)?.errorDescription {
            return localized
        }
        return String(describing: error)
    }
}
