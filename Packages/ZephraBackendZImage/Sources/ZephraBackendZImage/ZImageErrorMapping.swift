import Foundation
import Hub
import ZephraCore
import ZephraSnapshot
import ZImage

/// Turns errors thrown by the vendored library into `BackendError` values whose messages are
/// safe to put in front of a person, and says which of them are worth retrying.
///
/// Only the classification lives here. Pulling a readable string out of an arbitrary error is
/// `Error.readableMessage` in `ZephraCore`, because nothing about it is Z-Image's business.
nonisolated enum ZImageErrorMapping {
    /// Classifies a model-resolution failure once the retries are spent.
    ///
    /// A missing repository means the weights are not obtainable at all. A refused token is
    /// named as such, with where the token came from, because every model in the catalog is
    /// public and the token is the only thing that can be wrong. Anything else is a transfer
    /// that broke, and the message says that trying again picks it up where it stopped.
    static func downloadError(
        _ error: ModelResolutionError,
        descriptor: ModelDescriptor
    ) -> BackendError {
        switch error {
        case .modelNotFound:
            .modelNotAvailable(descriptor.fullName)
        case .authorizationRequired:
            .downloadFailed(HubToken.refusalMessage())
        case .networkUnavailable:
            .downloadFailed(DownloadRetry.givingUpMessage(offlineReason))
        case .downloadFailed(_, let underlying):
            .downloadFailed(DownloadRetry.givingUpMessage(reason(for: underlying)))
        }
    }

    /// Why a transfer stopped, in the app's words where the library's would not do: the
    /// library says "please check your network or use a local model path", and the person
    /// reading it has neither a path nor a way to give one.
    static func reason(for error: any Error) -> String {
        if case HubApi.EnvironmentError.offlineModeError = error { return offlineReason }
        return error.readableMessage
    }

    private static let offlineReason =
        "This Mac is offline, or on a connection the downloader treats as metered."

    /// Whether another try could end differently. No such repository and a refused token are
    /// answers, not accidents; so is any client-side status other than a timeout or a
    /// rate limit. A dropped connection, a server error, or the hub client's own offline
    /// verdict are the things a pause and another try are for.
    static func isPermanent(_ error: any Error) -> Bool {
        switch error {
        case ModelResolutionError.modelNotFound, ModelResolutionError.authorizationRequired:
            return true
        case ModelResolutionError.downloadFailed(_, let underlying):
            return isPermanent(underlying)
        case Hub.HubClientError.authorizationRequired, Hub.HubClientError.fileNotFound,
             Hub.HubClientError.resourceNotFound:
            return true
        case Hub.HubClientError.httpStatusCode(let code):
            return (400..<500).contains(code) && code != 408 && code != 429
        default:
            return false
        }
    }
}
