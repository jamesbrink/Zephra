import Foundation
import ZephraCore

/// Turning one directory into the row Settings > Models shows for it. Split out of
/// `ModelStorage.swift` so that file is the walk over the catalog and nothing else.
extension ModelStorage {
    /// Keeps one row per directory: a release two models pack from is claimed by both rather
    /// than listed twice.
    static func add(_ item: ModelStorageItem?, to items: inout [ModelStorageItem]) {
        guard let item else { return }
        if let index = items.firstIndex(where: { $0.url == item.url }) {
            items[index] = items[index].alsoUsed(by: item.modelIDs)
        } else {
            items.append(item)
        }
    }

    static func download(
        _ descriptor: ModelDescriptor, at url: URL, isComplete: Bool, in locations: ModelLocations,
        origin: ModelStorageItem.Origin = .appFolder
    ) -> ModelStorageItem {
        let name = descriptor.isBuiltLocally
            ? "\(descriptor.displayName) release" : descriptor.fullName
        return ModelStorageItem(
            name: name, kind: .download, url: url, location: place(of: url, in: locations),
            modelIDs: [descriptor.id], isComplete: isComplete, origin: origin)
    }

    /// The same adapter where `hf download` put it: the whole repository directory in the hub
    /// cache, blobs and bookkeeping included, which is what deleting it removes.
    static func adapter(
        _ adapter: ModelAdapter, of descriptor: ModelDescriptor, at repository: HubRepository,
        captioned locations: ModelLocations
    ) -> ModelStorageItem {
        ModelStorageItem(
            name: "\(descriptor.displayName) adapter", kind: .download, url: repository.url,
            location: place(of: repository.url, in: locations), modelIDs: [descriptor.id],
            isComplete: repository.file(adapter.file, revision: adapter.revision) != nil,
            origin: .hubCache)
    }

    /// An adapter's download, listed with the model it serves rather than on its own: it is one
    /// file in a repository of its own, and deleting it costs that model its distillation.
    static func adapter(
        _ adapter: ModelAdapter, of descriptor: ModelDescriptor, in folder: ModelLocations,
        captioned locations: ModelLocations
    ) -> ModelStorageItem? {
        let directory = folder.adapter(adapter)
        guard HubCache.isDirectory(directory) else { return nil }
        let file = folder.adapterFile(adapter)
        return ModelStorageItem(
            name: "\(descriptor.displayName) adapter", kind: .download, url: directory,
            location: place(of: directory, in: locations), modelIDs: [descriptor.id],
            isComplete: FileManager.default.fileExists(atPath: file.path(percentEncoded: false)))
    }

    static func built(
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
            isComplete: isComplete, origin: origin, bytes: bytes)
    }
}
