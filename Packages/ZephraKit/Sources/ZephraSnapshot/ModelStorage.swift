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
            switch descriptor.source {
            case .localDirectory:
                // The folder this root says the variant is in, and only that one. A copy left
                // behind in a folder the user has since changed away from still loads — the
                // backends look there too — but it is not this folder's business to list.
                if let directory = locations.builtCandidates(for: descriptor).first {
                    add(built(descriptor, at: directory, in: locations), to: &items)
                }
            case .huggingFace(let repoID, _, _):
                let downloads = locations.downloads(repoID: repoID)
                if HubCache.isDirectory(downloads) {
                    add(
                        download(
                            descriptor, at: downloads,
                            isComplete: HubSnapshotCheck.isComplete(downloads), in: locations),
                        to: &items)
                }
                for repository in HubCache.repositories(of: repoID, in: cache) {
                    add(
                        download(
                            descriptor, at: repository.url, isComplete: repository.isComplete,
                            in: locations),
                        to: &items)
                }
                for item in descriptor.adapters {
                    add(adapter(item, of: descriptor, in: locations), to: &items)
                }
                if descriptor.isBuiltLocally {
                    add(
                        built(descriptor, at: locations.built(descriptor), in: locations),
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

    /// Keeps one row per directory: a release two models pack from is claimed by both rather
    /// than listed twice.
    private static func add(_ item: ModelStorageItem?, to items: inout [ModelStorageItem]) {
        guard let item else { return }
        if let index = items.firstIndex(where: { $0.url == item.url }) {
            items[index] = items[index].alsoUsed(by: item.modelIDs)
        } else {
            items.append(item)
        }
    }

    private static func download(
        _ descriptor: ModelDescriptor, at url: URL, isComplete: Bool, in locations: ModelLocations
    ) -> ModelStorageItem {
        let name = descriptor.isBuiltLocally
            ? "\(descriptor.displayName) release" : descriptor.fullName
        return ModelStorageItem(
            name: name, kind: .download, url: url, location: place(of: url, in: locations),
            modelIDs: [descriptor.id], isComplete: isComplete)
    }

    /// An adapter's download, listed with the model it serves rather than on its own: it is one
    /// file in a repository of its own, and deleting it costs that model its distillation.
    private static func adapter(
        _ adapter: ModelAdapter, of descriptor: ModelDescriptor, in locations: ModelLocations
    ) -> ModelStorageItem? {
        let directory = locations.adapter(adapter)
        guard HubCache.isDirectory(directory) else { return nil }
        let file = locations.adapterFile(adapter)
        return ModelStorageItem(
            name: "\(descriptor.displayName) adapter", kind: .download, url: directory,
            location: place(of: directory, in: locations), modelIDs: [descriptor.id],
            isComplete: FileManager.default.fileExists(atPath: file.path(percentEncoded: false)))
    }

    private static func built(
        _ descriptor: ModelDescriptor, at directory: URL, in locations: ModelLocations
    ) -> ModelStorageItem? {
        guard HubCache.isDirectory(directory) else { return nil }
        return ModelStorageItem(
            name: descriptor.fullName, kind: .built, url: directory,
            location: place(of: directory, in: locations), modelIDs: [descriptor.id],
            isComplete: true)
    }

    /// Where a row is, as a row should say it: the path under the folder models are kept in,
    /// which is short and tells one download from another, or the whole path when it is
    /// somewhere else — the hub cache, or a folder left behind by an earlier choice.
    private static func place(of url: URL, in locations: ModelLocations) -> String {
        let root = folder(locations.root) + "/"
        let path = folder(url)
        guard path.hasPrefix(root) else { return path }
        return String(path.dropFirst(root.count))
    }

    private static func folder(_ url: URL) -> String {
        let path = url.standardizedFileURL.path(percentEncoded: false)
        return path.count > 1 && path.hasSuffix("/") ? String(path.dropLast()) : path
    }
}

extension ModelStorageItem {
    /// The same directory, now also claimed by more models. A release the download's own model
    /// loads keeps that model's name; one only packed from keeps the family's.
    fileprivate func alsoUsed(by others: [ModelDescriptor.ID]) -> ModelStorageItem {
        ModelStorageItem(
            name: name, kind: kind, url: url, location: location,
            modelIDs: modelIDs + others.filter { !modelIDs.contains($0) },
            isComplete: isComplete, bytes: bytes)
    }
}
