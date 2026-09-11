import Foundation

/// How much of the Mac's library the phone will hold in whole files, and which files go first
/// when it holds too much.
///
/// Half a gigabyte, which is thirty or so pictures and a handful of clips: enough that the
/// things looked at this afternoon are still there on the train home, and little enough that
/// nobody ever wonders why Zephra is the largest app on their phone. A thumbnail is not
/// counted — the whole point of the thumbnails is that they are what makes the library
/// browsable offline, and they are kilobytes each.
///
/// Oldest read goes first, not oldest fetched. A clip watched four times today is worth more
/// than a picture fetched once this morning, and the access date is the only thing that says
/// so. Pure, so the rule is tested rather than observed.
nonisolated enum CacheBudget {
    /// What the files folder may hold, in bytes.
    static let bytes: Int64 = 512 * 1_048_576

    /// One file in the cache, as the budget sees it.
    struct File: Hashable, Sendable {
        /// Where it is.
        var url: URL
        /// How many bytes it takes.
        var size: Int64
        /// When it was last read, which is what decides whether it stays.
        var accessedAt: Date

        /// A file the budget can weigh.
        init(url: URL, size: Int64, accessedAt: Date) {
            self.url = url
            self.size = size
            self.accessedAt = accessedAt
        }
    }

    /// Which files to drop to bring the folder back under `limit`, least recently read first.
    ///
    /// Empty when the folder already fits, which is the usual answer and costs nothing.
    static func excess(of files: [File], limit: Int64 = bytes) -> [File] {
        var total = files.reduce(Int64(0)) { $0 + $1.size }
        guard total > limit else { return [] }
        var dropped: [File] = []
        for file in files.sorted(by: { $0.accessedAt < $1.accessedAt }) {
            dropped.append(file)
            total -= file.size
            if total <= limit { break }
        }
        return dropped
    }
}
