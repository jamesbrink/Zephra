import Foundation
import ZephraCore

/// What the catalog's models occupy on this Mac, found from the disk alone.
///
/// Two places are looked at. The folder the user keeps models in — downloads under
/// `Downloads/<org>--<repo>`, variants packed here beside them — and the hub cache, in either of
/// its layouts, for anything `hf` or an older Zephra left there. Nothing else is measured or
/// offered for deletion, so a folder of the user's own beside them is never touched.
public nonisolated enum ModelStorage {
    /// Every directory the catalog's models have on this Mac, unmeasured, in catalog order and
    /// with the app's own folder before the hub cache.
    ///
    /// A release several models pack from is listed once, naming all of them. A model whose
    /// download is what loads is the download's name; a release only ever packed from is
    /// called the family's release, so a row reads as what deleting it would cost. Each row
    /// also says where it is, which is what tells two copies of one release apart.
    public static func items(
        for catalog: [ModelDescriptor],
        cache: URL = HubCache.directory(),
        locations: ModelLocations = .default
    ) -> [ModelStorageItem] {
        var items: [ModelStorageItem] = []
        for descriptor in catalog {
            // Every root the folder has been, the current one first: what was downloaded or
            // built under an earlier choice still loads, so it is still the person's to see
            // and to delete. A row under a root other than the current one says its whole path.
            for root in locations.roots {
                let folder = ModelLocations(root: root)
                switch descriptor.source {
                case .localDirectory:
                    if let directory = folder.builtCandidates(for: descriptor).first {
                        add(built(descriptor, at: directory, in: locations), to: &items)
                    }
                case .huggingFace(let repoID, _, _):
                    let downloads = folder.downloads(repoID: repoID)
                    if HubCache.isDirectory(downloads) {
                        add(
                            download(
                                descriptor, at: downloads,
                                isComplete: HubSnapshotCheck.isComplete(downloads), in: locations),
                            to: &items)
                    }
                    for item in descriptor.adapters {
                        add(adapter(item, of: descriptor, in: folder, captioned: locations), to: &items)
                    }
                    if descriptor.isBuiltLocally {
                        add(built(descriptor, at: folder.built(descriptor), in: locations), to: &items)
                    }
                }
            }
            if case .huggingFace(let repoID, _, _) = descriptor.source {
                for repository in HubCache.repositories(of: repoID, in: cache) {
                    add(
                        download(
                            descriptor, at: repository.url, isComplete: repository.isComplete,
                            in: locations),
                        to: &items)
                }
            }
        }
        return items
    }

    /// The bytes the files under `url` occupy on disk, walked without following links: in the
    /// `hf` layout every snapshot is a set of links into the blob store, and the blobs are what
    /// the disk is holding.
    public static func measure(_ url: URL) -> Int64 {
        let keys: Set<URLResourceKey> = [.isSymbolicLinkKey, .totalFileAllocatedSizeKey]
        guard let walk = FileManager.default.enumerator(
            at: url, includingPropertiesForKeys: Array(keys), options: [.producesRelativePathURLs])
        else { return 0 }
        var total: Int64 = 0
        for case let file as URL in walk {
            guard let values = try? file.resourceValues(forKeys: keys),
                  values.isSymbolicLink != true
            else { continue }
            total += Int64(values.totalFileAllocatedSize ?? 0)
        }
        return total
    }

    /// Moves the item's directory to the Trash, where it can be put back. Nothing is unlinked
    /// on the user's behalf: a mistaken click on twenty gigabytes is undone from the Finder.
    public static func remove(_ item: ModelStorageItem) throws {
        try FileManager.default.trashItem(at: item.url, resultingItemURL: nil)
    }
}
