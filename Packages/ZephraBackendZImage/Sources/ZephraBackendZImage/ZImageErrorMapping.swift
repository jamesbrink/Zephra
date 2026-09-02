import Foundation
import ZephraCore
import ZImage

/// Turns errors thrown by the vendored library into `BackendError` values whose messages are
/// safe to put in front of a person.
///
/// Only the classification lives here. Pulling a readable string out of an arbitrary error is
/// `Error.readableMessage` in `ZephraCore`, because nothing about it is Z-Image's business.
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
            .downloadFailed(error.readableMessage)
        }
    }
}
