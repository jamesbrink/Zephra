import Foundation
import ZephraSnapshot

/// Where the updater is, which is the whole of what the banner draws.
///
/// A release the checker found sits at `available` and **nothing is fetched** until somebody
/// presses Update Now: a few hundred megabytes is not something to spend on a Mac's behalf
/// because it happened to be six hours since the last check.
enum UpdatePhase: Hashable, Sendable {
    /// Nothing found, nothing asked for.
    case idle
    /// A check is in flight.
    case checking
    /// A newer release is published, and has not been fetched.
    case available(ReleaseManifest)
    /// Its disk image is coming down; the fraction is of the whole file.
    case downloading(ReleaseManifest, fraction: Double)
    /// The image is on disk and its checksum is the published one.
    case ready(ReleaseManifest, image: URL)
    /// The image is being verified and copied into place, after which the app quits.
    case installing(ReleaseManifest)
    /// It did not work, in the words the person reading it needs.
    case failed(reason: String)

    /// The release this phase is about, when it is about one.
    var release: ReleaseManifest? {
        switch self {
        case .available(let release), .downloading(let release, _), .installing(let release):
            release
        case .ready(let release, _):
            release
        case .idle, .checking, .failed:
            nil
        }
    }

    /// Whether the updater is busy with something a second press would duplicate.
    var isWorking: Bool {
        switch self {
        case .checking, .downloading, .installing: true
        case .idle, .available, .ready, .failed: false
        }
    }
}
