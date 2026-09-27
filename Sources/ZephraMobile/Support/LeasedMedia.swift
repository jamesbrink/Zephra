import Foundation

/// Ownership travels with the URL, including after the presenting view disappears.
nonisolated struct LeasedMedia: Sendable {
    let url: URL
    let lease: FileLease
}
