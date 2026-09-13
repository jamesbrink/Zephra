import Foundation
import ZephraLinkProtocol

/// Legacy rows had no host identity. Preserve them separately until a host verifies ownership.
nonisolated enum LibraryCacheMigration {
    static func quarantine(_ root: URL) throws {
        let marker = root.appending(path: "host-cache-v2")
        guard !FileManager.default.fileExists(atPath: marker.path) else { return }
        let legacy = root.appending(path: "Legacy")
        try CacheDirectories.prepare(legacy)
        for name in ["Entries", "Thumbnails"] {
            let source = root.appending(path: name), target = legacy.appending(path: name)
            if FileManager.default.fileExists(atPath: source.path) && !FileManager.default.fileExists(atPath: target.path) {
                try FileManager.default.moveItem(at: source, to: target)
            }
        }
        try Data("2".utf8).write(to: marker, options: .atomic)
    }
}
