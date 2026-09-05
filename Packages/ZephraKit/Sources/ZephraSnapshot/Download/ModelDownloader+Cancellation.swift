import Foundation

extension ModelDownloader {
    /// Called after the transfer has unwound and closed its files, including cancellation
    /// during retry backoff. Only this fetch's writable destinations are eligible; cached
    /// releases and previous roots never enter this list.
    static func discardUnfinished(_ parts: [RepositoryDownload], under root: URL) throws {
        let files = FileManager.default
        for destination in Set(parts.map(\.destination)) {
            guard files.fileExists(atPath: destination.path) else { continue }
            guard !isLink(destination),
                  isContained(destination.lastPathComponent, target: destination, in: root)
            else {
                throw ModelDownloadError.unsafePath(path: destination.path)
            }
            let pin = pin(in: destination)
            let partials = HubSnapshotCheck.incompleteFiles(in: destination)
            guard files.fileExists(atPath: pin.path) || !partials.isEmpty else { continue }
            // A finished repository may also hold another adapter being fetched. Preserve
            // its completed files; a new, unfinished repository goes in its entirety,
            // including whole shards that are useless without the rest of that model.
            if files.fileExists(atPath: completed(in: destination).path) {
                for partial in partials {
                    guard isContained(partial.lastPathComponent, target: partial, in: destination) else {
                        throw ModelDownloadError.unsafePath(path: partial.path)
                    }
                    try files.removeItem(at: partial)
                    let validator = validator(of: partial)
                    if files.fileExists(atPath: validator.path) { try files.removeItem(at: validator) }
                }
                if files.fileExists(atPath: pin.path) { try files.removeItem(at: pin) }
            } else {
                try files.removeItem(at: destination)
            }
        }
    }
}
