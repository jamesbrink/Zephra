import Foundation
import ZephraCore

/// Why a release's disk image did not arrive.
public enum UpdateDownloadError: Error, Hashable, Sendable {
    /// The transfer broke: the connection went, or the body ended early.
    case interrupted(reason: String)
    /// The host answered with a status that is not 200.
    case refused(status: Int)
    /// The image arrived whole and its digest was not the one the manifest published.
    case checksumMismatch
    /// The manifest's build is not a twelve-digit stamp, so it names no release of ours — and
    /// it is what the downloaded file is named after, so it never reaches the file system.
    case notARelease

    /// Whether another try could end differently. A refusal and a mismatched digest are both
    /// answers about the bytes on the server, not accidents on the way here.
    public var isPermanent: Bool {
        switch self {
        case .interrupted: false
        case .refused(let status): DownloadRetry.isPermanentStatus(status)
        case .checksumMismatch, .notARelease: true
        }
    }

    /// What to tell someone, without the jargon of the layer it came from.
    public var message: String {
        switch self {
        case .interrupted(let reason):
            "The download stopped: \(reason)"
        case .refused(let status):
            "The update server refused to serve the download (HTTP \(status))."
        case .checksumMismatch:
            "The download did not match its published checksum, so it was discarded."
        case .notARelease:
            "The update server named something that is not a Zephra release."
        }
    }
}
