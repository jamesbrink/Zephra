import Foundation

extension LibraryCatalog {
    func leasedMedia(for entry: CachedEntry) async throws -> LeasedMedia {
        let lease = await lease(entry)
        let url = try await file(for: entry)
        return LeasedMedia(url: url, lease: lease)
    }
}
