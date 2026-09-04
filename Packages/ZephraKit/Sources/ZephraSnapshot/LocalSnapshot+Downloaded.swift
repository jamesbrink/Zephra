import Foundation
import ZephraCore

extension LocalSnapshot {
    /// Where `descriptor`'s download is on this Mac, or nil when it is not here.
    ///
    /// Two places, in the order every backend looks at them: the folder the user keeps models
    /// in, and then the Hugging Face cache in either layout. The cache is a fallback and is only
    /// ever read — a Mac that ran `hf download`, or that downloaded with an older Zephra, should
    /// not fetch thirty gigabytes it already has — but nothing is written there any more.
    ///
    /// The receiver says what the directory must hold, which is not the same question for every
    /// model: for one whose download is what loads, it is the loader's own list; for one packed
    /// here, it is what the packer reads. And a descriptor's adapters count. A release whose
    /// distillation never arrived is not something a variant can be built from, and reporting it
    /// as a finished download would send the build off to fail instead of fetching the 1.7 GB
    /// that is missing.
    public func downloadedRelease(
        of descriptor: ModelDescriptor, in locations: ModelLocations
    ) -> URL? {
        guard case .huggingFace(let repoID, let revision, _) = descriptor.source else { return nil }
        let files = FileManager.default
        guard descriptor.adapters.allSatisfy({
            files.fileExists(atPath: locations.adapterFile($0).path(percentEncoded: false))
        }) else { return nil }

        let downloads = locations.downloads(repoID: repoID)
        if missingEntry(in: downloads) == nil, HubSnapshotCheck.isComplete(downloads) {
            return downloads
        }
        if let cached = HubCache.snapshot(of: repoID, revision: revision),
           missingEntry(in: cached) == nil
        {
            return cached
        }
        return nil
    }
}
