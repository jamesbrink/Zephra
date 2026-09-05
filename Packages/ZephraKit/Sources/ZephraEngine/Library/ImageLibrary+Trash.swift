import Foundation

/// Deleting an image without losing it: a folder inside the library, the way Photos does it,
/// rather than the Finder's Trash. Restoring is then a click instead of an excursion, and the
/// thirty days are ours to enforce.
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

    /// Moves an image into Recently Deleted and writes down when, so its thirty days can start.
    /// Returns where it landed, which is a stepped-around name if something was already called
    /// that.
    @discardableResult
    public func moveToRecentlyDeleted(_ url: URL, at date: Date = Date()) throws -> URL {
        let folder = directory(for: .recentlyDeleted)
        try ImageDirectoryAccess.prepare(folder)
        let target = availableURL(named: url.lastPathComponent, in: folder)
        try FileManager.default.moveItem(at: url, to: target)
        var manifest = recentlyDeletedManifest()
        manifest.record(target.lastPathComponent, at: date)
        try write(manifest)
        return target
    }

    /// Moves an image back into the library and forgets it was ever deleted. Returns where it
    /// landed, which is a stepped-around name if the original one has been taken since.
    @discardableResult
    public func restoreFromRecentlyDeleted(_ url: URL) throws -> URL {
        try ImageDirectoryAccess.prepare(root)
        let target = availableURL(named: url.lastPathComponent, in: root)
        try FileManager.default.moveItem(at: url, to: target)
        var manifest = recentlyDeletedManifest()
        manifest.forget(url.lastPathComponent)
        try write(manifest)
        return target
    }

    /// Discards everything deleted before `cutoff`, and returns what went.
    ///
    /// A file nobody wrote down — put there by hand, or left by a build that crashed between
    /// the move and the manifest — is recorded as deleted now and kept, but only if Zephra made
    /// it. It gets the full thirty days from the moment it was noticed rather than being purged
    /// on the spot, because the alternative is deleting somebody's picture over a missing line
    /// in a JSON file, and a picture Zephra did not make is never deleted at all: this folder is
    /// inside the user's Pictures, and anything else in it is theirs.
    @discardableResult
    public func purgeRecentlyDeleted(deletedBefore cutoff: Date, now: Date = Date()) throws -> [URL] {
        let folder = directory(for: .recentlyDeleted)
        let files = (try? FileManager.default.contentsOfDirectory(
            at: folder,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles, .skipsSubdirectoryDescendants]
        )) ?? []
        let before = recentlyDeletedManifest()
        var manifest = before
        var purged: [URL] = []
        for url in files where url.pathExtension.lowercased() == "png" {
            let name = url.lastPathComponent
            guard let deletedAt = manifest.deletedAt(name) else {
                guard isOurs(url) else { continue }
                manifest.record(name, at: now)
                continue
            }
            guard deletedAt < cutoff else { continue }
            try discard(url)
            manifest.forget(name)
            purged.append(url)
        }
        // Only when it changed: this runs on every scan, and a write here would move the folder,
        // which would wake the folder watch, which would scan again.
        if manifest != before { try write(manifest) }
        return purged
    }

    /// Whether a file carries a Zephra record, which is what makes it ours to delete.
    private func isOurs(_ url: URL) -> Bool {
        guard let text = try? PNGTextChunks.read(fromHeaderOf: url) else { return false }
        return GenerationRecord.decode(from: text) != nil || SourceRecord.decode(from: text) != nil
    }

    private func write(_ manifest: RecentlyDeletedManifest) throws {
        let folder = directory(for: .recentlyDeleted)
        try ImageDirectoryAccess.prepare(folder)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys, .prettyPrinted, .withoutEscapingSlashes]
        try encoder.encode(manifest).write(to: recentlyDeletedManifestURL, options: .atomic)
    }
}
