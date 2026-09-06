import CryptoKit
import Foundation

/// The SHA-256 of a file, read in pieces so a twenty-gigabyte shard is never in memory whole.
enum FileDigest {
    /// The digest as lowercase hex, the way the mirror's index writes it.
    static func sha256(of url: URL) throws -> String {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        var hasher = SHA256()
        while let chunk = try handle.read(upToCount: 8 << 20), !chunk.isEmpty {
            try Task.checkCancellation()
            hasher.update(data: chunk)
        }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }
}
