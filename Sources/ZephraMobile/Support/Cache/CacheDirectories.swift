import Foundation

/// Where the phone keeps what it has been told, and the two rules about those folders.
///
/// Two places, on purpose. The entries and their thumbnails are what makes the library
/// browsable with no Mac in reach, so they go in Application Support, which iOS does not
/// reclaim. Whole files and clips are megabytes each and can always be fetched again, so they
/// go in Caches, which iOS may empty under pressure — and which the budget empties first.
///
/// Neither is backed up. The Mac's folder is the truth; a restore that carried a stale copy of
/// somebody's library onto a new phone would be paying for the same bytes twice.
nonisolated enum CacheDirectories {
    /// Everything kept for good: the entries and the thumbnails drawn from them.
    static func library() throws -> URL {
        let root = try FileManager.default.url(
            for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil,
            create: true
        ).appending(path: "Library", directoryHint: .isDirectory)
        try prepare(root)
        return root
    }

    /// Whole pictures and clips, which iOS may take back whenever it likes.
    static func files() throws -> URL {
        let root = try FileManager.default.url(
            for: .cachesDirectory, in: .userDomainMask, appropriateFor: nil, create: true
        ).appending(path: "Files", directoryHint: .isDirectory)
        try prepare(root)
        return root
    }

    /// Makes a folder if it is not there and keeps it out of the backup.
    static func prepare(_ directory: URL) throws {
        var folder = directory
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        try? folder.setResourceValues(values)
    }

    /// How many bytes a folder holds, counting everything under it.
    static func size(of directory: URL) -> Int64 {
        let files = FileManager.default
        guard let walk = files.enumerator(
            at: directory, includingPropertiesForKeys: [.fileSizeKey, .isRegularFileKey])
        else { return 0 }
        var total: Int64 = 0
        for case let url as URL in walk {
            let facts = try? url.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey])
            guard facts?.isRegularFile == true else { continue }
            total += Int64(facts?.fileSize ?? 0)
        }
        return total
    }

    /// Empties a folder, leaving the folder itself where it is.
    static func empty(_ directory: URL) {
        let files = FileManager.default
        let contents = (try? files.contentsOfDirectory(atPath: directory.path(percentEncoded: false)))
            ?? []
        for name in contents {
            try? files.removeItem(at: directory.appending(path: name))
        }
    }
}
