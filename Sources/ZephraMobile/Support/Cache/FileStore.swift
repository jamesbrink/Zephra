import Foundation

/// Whole pictures and clips, under `Caches/Files/`.
///
/// The name on disk is the name in the Mac's library folder, and a clip's MP4 sits beside its
/// poster under the same stem — `VideoSidecar`'s rule, which is the Mac's rule, so a phone and
/// a Mac never disagree about where a clip is. Two files for one picture, and the budget
/// weighs both.
///
/// In Caches rather than Application Support because these are the bytes that can always be
/// fetched again: iOS may take the folder back under pressure and nothing is lost but a wait.
/// `CacheBudget` empties it first, least recently read going first.
actor FileStore {
    /// Where the files are, or nil for a store that keeps nothing.
    private let directory: URL?
    /// What the folder may hold. A parameter only so a test can fill it without half a
    /// gigabyte of fixtures.
    private let limit: Int64

    /// A store under one caches root.
    init(root: URL?, limit: Int64 = CacheBudget.bytes) {
        directory = root
        self.limit = limit
        if let root { try? CacheDirectories.prepare(root) }
    }

    /// The file already held under this name, or nil. Reading one marks it as read, which is
    /// what keeps it: the budget drops whatever has gone longest unlooked-at.
    func url(for fileName: String) -> URL? {
        guard let url = path(for: fileName),
            FileManager.default.fileExists(atPath: url.path(percentEncoded: false))
        else { return nil }
        touch(url)
        return url
    }

    /// Keeps one file's bytes and answers where they landed, trimming the folder afterwards if
    /// it has grown past the budget.
    @discardableResult
    func store(_ data: Data, as fileName: String) -> URL? {
        guard let url = path(for: fileName) else { return nil }
        try? data.write(to: url, options: .atomic)
        touch(url)
        trim()
        return url
    }

    /// Empties the folder.
    func clear() {
        guard let directory else { return }
        CacheDirectories.empty(directory)
    }

    /// How many bytes the files occupy.
    func size() -> Int64 {
        directory.map(CacheDirectories.size(of:)) ?? 0
    }

    /// Drops least recently read files until the folder fits.
    func trim() {
        guard let directory else { return }
        for file in CacheBudget.excess(of: Self.contents(of: directory), limit: limit) {
            try? FileManager.default.removeItem(at: file.url)
        }
    }

    /// Where one name would live, whether or not anything is there.
    private func path(for fileName: String) -> URL? {
        directory?.appending(path: fileName)
    }

    /// Records that a file was just read.
    ///
    /// The access date is set explicitly rather than left to the file system: iOS mounts with
    /// `noatime`, so a read on its own changes nothing and every file would look equally old.
    /// The modification date follows it, since these bytes never change after they are written
    /// and a folder read back by anything else should still say when it was last wanted.
    private func touch(_ url: URL) {
        var file = url
        var values = URLResourceValues()
        let now = Date()
        values.contentAccessDate = now
        values.contentModificationDate = now
        try? file.setResourceValues(values)
    }

    /// Every file in the folder, with what the budget weighs it by.
    private static func contents(of directory: URL) -> [CacheBudget.File] {
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
