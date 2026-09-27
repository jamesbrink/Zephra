import Foundation

extension ThumbnailStore {
    static func key(_ entry: CachedEntry, pixels: Int) -> String {
        digest(fileName: entry.hostID == nil ? entry.fileName : entry.fileName + ":" + entry.version,
            contentModifiedAt: entry.contentModifiedAt, pixels: pixels)
    }

    /// The retained catalog includes offline entries; it is never a partial remote page.
    func retain(_ entries: [CachedEntry], ticket: UUID? = nil) {
        guard ticket == nil || ticket == generation else { return }
        let keys = Set(entries.flatMap { entry in
            [Self.cellPixels, Self.viewerPixels].map { Self.key(entry, pixels: $0) }
        })
        retained = keys
        guard let directory,
              let walk = FileManager.default.enumerator(at: directory, includingPropertiesForKeys: nil) else { return }
        for case let url as URL in walk where url.pathExtension == "jpg" {
            if !keys.contains(url.deletingPathExtension().lastPathComponent) {
                try? FileManager.default.removeItem(at: url)
            }
        }
    }
}
