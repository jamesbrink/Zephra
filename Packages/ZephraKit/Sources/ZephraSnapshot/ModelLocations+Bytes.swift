import Foundation
import ZephraCore

/// What choosing a model would still cost in bytes.
///
/// Answered here rather than in `ZephraCore` because the question is about what is on this
/// Mac, which that layer does not look at; the caller has already asked whether the release is
/// present, hub cache included.
extension ModelLocations {
    /// What choosing `descriptor` would still transfer: its release, unless that is already
    /// here. This is what a picker states, so a release found in the cache reads as nothing
    /// left to fetch rather than as the whole download over again.
    public func bytesToFetch(
        for descriptor: ModelDescriptor, releasePresent: Bool, cache: URL = HubCache.directory()
    ) -> Int64 {
        releasePresent ? 0 : descriptor.downloadBytes
    }
}
