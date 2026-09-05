import Foundation

/// Emptying Recently Deleted of what has waited its thirty days.
extension ImageLibrary {
    /// Discards everything deleted before `cutoff`, and returns what went.
    ///
    /// Ownership is checked for every candidate, entry or not, because the manifest names a
    /// file and a name can be reused: a picture Zephra did not make is never deleted, whatever
    /// the manifest remembers under its name, and its entry is dropped. A file nobody wrote
    /// down — put there by hand, or left by a build that crashed between the move and the
    /// manifest — is recorded as deleted now and kept. It gets the full thirty days from the
    /// moment it was noticed rather than being purged on the spot, because the alternative is
    /// deleting somebody's picture over a missing line in a JSON file. This folder is inside
    /// the user's Pictures, and anything else in it is theirs.
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
            guard isOurs(url) else {
                manifest.forget(name)
                continue
            }
            guard let deletedAt = manifest.deletedAt(name) else {
                manifest.record(name, at: now, origin: originByHeader(url))
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
    func isOurs(_ url: URL) -> Bool {
        guard let text = try? PNGTextChunks.read(fromHeaderOf: url) else { return false }
        return GenerationRecord.decode(from: text) != nil || SourceRecord.decode(from: text) != nil
    }
}
