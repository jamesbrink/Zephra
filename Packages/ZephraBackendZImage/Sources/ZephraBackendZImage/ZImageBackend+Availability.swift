import Foundation
import ZephraCore
import ZephraSnapshot

/// Answering "is this model on the machine?" from the disk alone. Split out of
/// `ZImageBackend.swift` so the loading and generating half of the backend reads on its own.
extension ZImageBackend {
    /// Says whether the weights are already on this Mac, reading the disk and nothing else.
    ///
    /// Three places are looked at, in the order `ensureAvailable` looks at them: the folder the
    /// user keeps models in, the hub cache for a release `hf` or an older Zephra put there, and
    /// for a local model the directory the catalog names. Nothing downloads, and nothing
    /// disturbs what is loaded, so a picker can label the whole catalog for free.
    nonisolated(nonsending) public func availability(
        of descriptor: ModelDescriptor,
        locations: ModelLocations
    ) async -> ModelAvailability {
        switch descriptor.source {
        case .localDirectory:
            let candidates = locations.builtCandidates(for: descriptor)
            guard candidates.allSatisfy({ LocalSnapshot.zImage.missingEntry(in: $0) != nil })
            else { return .available }
            let directory = candidates[0]
            let missing = LocalSnapshot.zImage.missingEntry(in: directory) ?? "its weights"
            return .missing(
                reason: """
                    \(descriptor.fullName) is not at \
                    \(directory.path(percentEncoded: false)): missing \(missing).
                    """
            )
        case .huggingFace(let repoID, let revision, _):
            guard Self.downloaded(descriptor, repoID: repoID, revision: revision, in: locations)
                == nil
            else { return .available }
            return .needsDownload(bytes: descriptor.downloadBytes)
        }
    }

    /// The finished download for `descriptor`, or nil when there is not one.
    ///
    /// The app's own folder first, then the hub cache in either layout. The cache is a
    /// fallback and is only ever read: a Mac that ran `make prefetch`, or that downloaded with
    /// an older Zephra, should not fetch thirteen gigabytes it already has, but nothing is
    /// written there any more.
    static func downloaded(
        _ descriptor: ModelDescriptor, repoID: String, revision: String, in locations: ModelLocations
    ) -> URL? {
        let downloads = locations.downloads(repoID: repoID)
        if LocalSnapshot.zImage.missingEntry(in: downloads) == nil,
           HubSnapshotCheck.isComplete(downloads)
        {
            return downloads
        }
        if let cached = HubCache.snapshot(of: repoID, revision: revision),
           LocalSnapshot.zImage.missingEntry(in: cached) == nil
        {
            return cached
        }
        return nil
    }
}
