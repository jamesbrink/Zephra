import Foundation
import ZephraCore

/// What the catalog's models occupy on this Mac, found from the disk alone.
///
/// Two places are looked at, the ones the catalog and the hub client already agree on: the hub
/// cache, in either of its layouts, for anything downloaded, and `localModelsDirectory` for
/// anything packed here. Nothing else is measured or offered for deletion, so a folder of the
/// user's own beside them is never touched.
public nonisolated enum ModelStorage {
    /// Every directory the catalog's models have on this Mac, unmeasured, in catalog order.
    ///
    /// A release several models pack from is listed once, naming all of them. A model whose
    /// download is what loads is the download's name; a release only ever packed from is
    /// called the family's release, so a row reads as what deleting it would cost.
    public static func items(
        for catalog: [ModelDescriptor],
        cache: URL = HubCache.directory(),
        builtIn models: URL = ModelCatalog.localModelsDirectory
    ) -> [ModelStorageItem] {
        var items: [ModelStorageItem] = []
        for descriptor in catalog {
            switch descriptor.source {
            case .localDirectory(let directory):
                items.append(contentsOf: built(descriptor, at: relocated(directory, into: models)))
            case .huggingFace(let repoID, _, _):
                for repository in HubCache.repositories(of: repoID, in: cache) {
                    if let index = items.firstIndex(where: { $0.url == repository.url }) {
                        items[index] = items[index].alsoUsed(by: descriptor)
                    } else {
                        items.append(download(descriptor, from: repository))
                    }
                }
                if descriptor.isBuiltLocally {
                    let packed = models.appending(path: descriptor.id, directoryHint: .isDirectory)
                    items.append(contentsOf: built(descriptor, at: packed))
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

    private static func download(
        _ descriptor: ModelDescriptor, from repository: HubRepository
    ) -> ModelStorageItem {
        let name = descriptor.isBuiltLocally ? "\(descriptor.displayName) release" : descriptor.fullName
        return ModelStorageItem(
            name: name, kind: .download, url: repository.url, modelIDs: [descriptor.id],
            isComplete: repository.isComplete)
    }

    /// A catalog entry names its directory absolutely, under the real `localModelsDirectory`.
    /// Read against another root — a test's scratch folder — the same entry means the same
    /// folder name under that root, so the whole catalog can be listed against any directory.
    private static func relocated(_ directory: URL, into models: URL) -> URL {
        let parent = directory.deletingLastPathComponent().standardizedFileURL.path(percentEncoded: false)
        let real = ModelCatalog.localModelsDirectory.standardizedFileURL.path(percentEncoded: false)
        guard parent == real else { return directory }
        return models.appending(path: directory.lastPathComponent, directoryHint: .isDirectory)
    }

    private static func built(_ descriptor: ModelDescriptor, at directory: URL) -> [ModelStorageItem] {
        guard HubCache.isDirectory(directory) else { return [] }
        return [
            ModelStorageItem(
                name: descriptor.fullName, kind: .built, url: directory,
                modelIDs: [descriptor.id], isComplete: true)
        ]
    }
}

extension ModelStorageItem {
    /// The same directory, now also claimed by `descriptor`. A release the download's own
    /// model loads keeps that model's name; one only packed from takes the family's.
    fileprivate func alsoUsed(by descriptor: ModelDescriptor) -> ModelStorageItem {
        ModelStorageItem(
            name: name, kind: kind, url: url, modelIDs: modelIDs + [descriptor.id],
            isComplete: isComplete, bytes: bytes)
    }
}
