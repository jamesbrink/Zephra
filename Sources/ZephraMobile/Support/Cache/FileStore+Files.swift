import Foundation

extension FileStore {
    /// Where one name would live, whether or not anything is there.
    func path(for fileName: String) -> URL? {
        directory?.appending(path: fileName)
    }

    /// Records that a file was just read.
    ///
    /// The access date is set explicitly rather than left to the file system: iOS mounts with
    /// `noatime`, so a read on its own changes nothing and every file would look equally old.
    /// The modification date follows it, since these bytes never change after they are written
    /// and a folder read back by anything else should still say when it was last wanted.
    func touch(_ url: URL) {
        var file = url
        var values = URLResourceValues()
        let now = Date()
        values.contentAccessDate = now
        values.contentModificationDate = now
        try? file.setResourceValues(values)
    }

    /// Every file in the folder, with what the budget weighs it by.
    static func contents(of directory: URL) -> [CacheBudget.File] {
        let keys: [URLResourceKey] = [.fileSizeKey, .contentAccessDateKey, .contentModificationDateKey]
        let urls = (try? FileManager.default.contentsOfDirectory(
            at: directory, includingPropertiesForKeys: keys)) ?? []
        return urls.compactMap { url in
            guard let facts = try? url.resourceValues(forKeys: Set(keys)) else { return nil }
            let accessed = facts.contentAccessDate ?? facts.contentModificationDate ?? .distantPast
            return CacheBudget.File(
                url: url, size: Int64(facts.fileSize ?? 0), accessedAt: accessed)
        }
    }
}
