import Foundation
import ZephraCore

extension ModelDownloader {
    /// Validate retained bytes before reserving only the missing bytes on their volume.
    func validateExistingFiles(_ work: [(part: RepositoryDownload, files: [RepositoryFile])]) throws {
        for (part, files) in work {
            for file in files where file.sha256 != nil {
                try Task.checkCancellation()
                let target = part.destination.appending(path: file.path)
                guard Self.isContained(file.path, target: target, in: part.destination) else {
                    throw ModelDownloadError.unsafePath(path: file.path)
                }
                for url in [target, Self.partial(of: target)] {
                    guard !Self.isLink(url), let size = Self.size(of: url), size == file.bytes else { continue }
                    if try !matchesDigest(file, at: url) {
                        try FileManager.default.removeItem(at: url)
                        if url == Self.partial(of: target) {
                            try? FileManager.default.removeItem(at: Self.validator(of: url))
                        }
                    }
                }
            }
        }
    }

    func matchesDigest(_ file: RepositoryFile, at url: URL) throws -> Bool {
        guard let expected = file.sha256 else { return true }
        return try FileDigest.sha256(of: url) == expected.lowercased()
    }
}
