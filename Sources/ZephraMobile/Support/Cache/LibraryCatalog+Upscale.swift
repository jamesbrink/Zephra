import Foundation
import ZephraLinkProtocol

extension LibraryCatalog {
    /// The entry's owning Mac performs the upscale, regardless of the watched destination.
    func upscale(_ entry: CachedEntry, factor: Int) async throws {
        if let child = owner(of: entry) {
            return try await child.upscale(entry, factor: factor)
        }
        guard entry.hostID == hostID else { throw LibraryCacheError.offline }
        guard !entry.isVideo, factor == 2 || factor == 4 else {
            throw LinkError(code: .unsupported, reason: "Choose a picture and a 2× or 4× upscale.")
        }
        guard let client, client.connection.isLive else { throw LibraryCacheError.offline }
        operations += 1
        defer { operations -= 1 }
        try await client.upscale(name: entry.fileName, factor: factor)
    }
}
