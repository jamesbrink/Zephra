import Foundation

/// Deleting an image without losing it: a folder inside the library, the way Photos does it,
/// rather than the Finder's Trash. Restoring is then a click instead of an excursion, and the
/// thirty days are ours to enforce. Emptying it is `ImageLibrary+Purge.swift`.
extension ImageLibrary {
    /// Where the deletion dates are written.
    public var recentlyDeletedManifestURL: URL {
        directory(for: .recentlyDeleted).appending(path: RecentlyDeletedManifest.fileName)
    }

    /// The deletion dates as they stand, or an empty manifest when there is no file, it cannot
    /// be read, or it was written by a build newer than this one.
    public func recentlyDeletedManifest() -> RecentlyDeletedManifest {
        guard let data = try? Data(contentsOf: recentlyDeletedManifestURL) else {
            return RecentlyDeletedManifest()
        }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        guard let manifest = try? decoder.decode(RecentlyDeletedManifest.self, from: data),
              manifest.version <= RecentlyDeletedManifest.currentVersion
        else { return RecentlyDeletedManifest() }
        return manifest
    }

    /// Moves an image into Recently Deleted and writes down when, and from which folder, so
    /// its thirty days can start and Put Back knows where to put it. Returns where it landed,
    /// which is a stepped-around name if something was already called that.
    @discardableResult
    public func moveToRecentlyDeleted(_ url: URL, at date: Date = Date()) throws -> URL {
        let folder = directory(for: .recentlyDeleted)
        try ImageDirectoryAccess.prepareForWrite(folder)
        let sidecar = VideoSidecar.existing(beside: url)
        let target = availableURL(named: url.lastPathComponent, in: folder)
        let origin: LibraryCollection =
            url.deletingLastPathComponent().standardizedFileURL
                == directory(for: .sources).standardizedFileURL ? .sources : .generated
        try Self.move(url, sidecar: sidecar, to: target)
        var manifest = recentlyDeletedManifest()
        manifest.record(target.lastPathComponent, at: date, origin: origin)
        try write(manifest)
        return target
    }

    /// Moves an image back into the folder it was deleted from — the manifest's word, else
    /// what its own header says — and forgets it was ever deleted. Returns where it landed,
    /// which is a stepped-around name if the original one has been taken since.
    @discardableResult
    public func restoreFromRecentlyDeleted(_ url: URL) throws -> URL {
        let name = url.lastPathComponent
        var manifest = recentlyDeletedManifest()
        let home = directory(for: manifest.origin(name) ?? originByHeader(url))
        try ImageDirectoryAccess.prepareForWrite(home)
        let sidecar = VideoSidecar.existing(beside: url)
        let target = availableURL(named: name, in: home)
        try Self.move(url, sidecar: sidecar, to: target)
        manifest.forget(name)
        try write(manifest)
        return target
    }

    /// Deletes one image for good, without waiting for its thirty days, and forgets its name,
    /// so a later file under that name gets its own thirty days rather than inheriting these.
    public func purgeFromRecentlyDeleted(_ url: URL) throws {
        try discard(url)
        let folder = directory(for: .recentlyDeleted)
        guard url.deletingLastPathComponent().standardizedFileURL == folder.standardizedFileURL
        else { return }
        var manifest = recentlyDeletedManifest()
        manifest.forget(url.lastPathComponent)
        try write(manifest)
    }

    /// Moves a picture to `target`, and its clip beside it under the target's stem, picture
    /// last: a clip whose poster has not moved yet is still listed where it was.
    static func move(_ url: URL, sidecar: URL?, to target: URL) throws {
        let files = FileManager.default
        if let sidecar {
            try files.moveItem(at: sidecar, to: VideoSidecar.url(beside: target))
        }
        do {
            try files.moveItem(at: url, to: target)
        } catch {
            // The poster stayed where it was listed; the clip goes back beside it.
            if let sidecar { try? files.moveItem(at: VideoSidecar.url(beside: target), to: sidecar) }
            throw error
        }
    }

    /// Where a file belongs by its own header: a source record makes it a source, anything
    /// else goes to the root.
    func originByHeader(_ url: URL) -> LibraryCollection {
        guard let text = try? PNGTextChunks.read(fromHeaderOf: url),
              SourceRecord.decode(from: text) != nil
        else { return .generated }
        return .sources
    }

    func write(_ manifest: RecentlyDeletedManifest) throws {
        let folder = directory(for: .recentlyDeleted)
        try ImageDirectoryAccess.prepareForWrite(folder)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys, .prettyPrinted, .withoutEscapingSlashes]
        try encoder.encode(manifest).write(to: recentlyDeletedManifestURL, options: .atomic)
    }
}
