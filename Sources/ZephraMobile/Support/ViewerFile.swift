import Foundation

/// A fetched URL belongs to one host-qualified entry and one version of its bytes.
nonisolated struct ViewerFile {
    let entry: CachedEntry
    let file: URL

    func url(for current: CachedEntry) -> URL? {
        entry.id == current.id && entry.version == current.version ? file : nil
    }
}
