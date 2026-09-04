import Foundation
import ZephraCore

/// Where a descriptor's adapters are on this Mac.
///
/// Answered here rather than in `ZephraCore`, because the answer takes in the hub cache, which
/// that layer does not know about: a Lightning adapter that `hf download` put beside the
/// release it distils is used from there and not fetched again, the way the release is.
/// The cache is only ever read; an adapter that is fetched lands under the root.
extension ModelLocations {
    /// The adapter file wherever it is — under this root, one the folder used to be, or the
    /// hub cache — or nil when it is nowhere: what a build is handed, and what says an adapter
    /// is not missing.
    public func adapterFileOnDisk(
        _ adapter: ModelAdapter, cache: URL = HubCache.directory()
    ) -> URL? {
        let files = FileManager.default
        let here = roots.map { ModelLocations(root: $0).adapterFile(adapter) }
            .first { files.fileExists(atPath: $0.path(percentEncoded: false)) }
        if let here { return here }
        return HubCache.repositories(of: adapter.repoID, in: cache)
            .lazy.compactMap { $0.file(adapter.file, revision: adapter.revision) }.first
    }

    /// The descriptor's adapters whose file is not here yet, and so still have to be fetched.
    public func missingAdapters(
        of descriptor: ModelDescriptor, cache: URL = HubCache.directory()
    ) -> [ModelAdapter] {
        descriptor.adapters.filter { adapterFileOnDisk($0, cache: cache) == nil }
    }

    /// What choosing `descriptor` would still transfer: the release unless it is already here,
    /// and every adapter that is not. This is what a picker states, so a release found in the
    /// cache with its distillation missing reads as the distillation's cost, not the release's.
    public func bytesToFetch(
        for descriptor: ModelDescriptor, releasePresent: Bool, cache: URL = HubCache.directory()
    ) -> Int64 {
        (releasePresent ? 0 : descriptor.downloadBytes)
            + missingAdapters(of: descriptor, cache: cache).reduce(0) { $0 + $1.bytes }
    }
}
