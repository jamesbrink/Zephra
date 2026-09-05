import Foundation

/// The two filesystem facts an export rests on: whether two paths are one file, and how to
/// put a copy where another file already is without a moment in which neither exists.
///
/// Both are `nonisolated`: they touch nothing but the disk.
extension ImageExport {
    /// Whether `a` and `b` name the same file: the same path once links are followed, or the
    /// same inode on the same volume, which is what a hard link — or the same volume mounted
    /// twice — looks like.
    nonisolated static func isSameFile(_ a: URL, _ b: URL) -> Bool {
        if a.standardizedFileURL.resolvingSymlinksInPath() == b.standardizedFileURL.resolvingSymlinksInPath() {
            return true
        }
        guard let idA = try? a.resourceValues(forKeys: [.fileResourceIdentifierKey]).fileResourceIdentifier,
            let idB = try? b.resourceValues(forKeys: [.fileResourceIdentifierKey]).fileResourceIdentifier
        else { return false }
        return idA.isEqual(idB)
    }

    /// Whether anything is at `url`.
    nonisolated static func exists(_ url: URL) -> Bool {
        FileManager.default.fileExists(atPath: url.path(percentEncoded: false))
    }

    /// Copies `source` to `destination`, replacing whatever is there.
    ///
    /// The copy lands in a hidden sibling in the destination's folder first — so it is on the
    /// destination's volume — and is then renamed into place: `replaceItemAt` when something is
    /// there, a plain move when nothing is. Both are one rename, so the destination is whole or
    /// absent at every instant, and the source is only ever read. Never remove-then-copy:
    /// that is how an export onto its own source deleted it.
    nonisolated static func copyReplacing(_ source: URL, to destination: URL) throws {
        let files = FileManager.default
        let staging = destination.deletingLastPathComponent()
            .appending(path: ".\(destination.lastPathComponent).zephra-export-\(UUID().uuidString)")
        try files.copyItem(at: source, to: staging)
        do {
            if exists(destination) {
                _ = try files.replaceItemAt(destination, withItemAt: staging)
            } else {
                try files.moveItem(at: staging, to: destination)
            }
        } catch {
            try? files.removeItem(at: staging)
            throw error
        }
    }
}
