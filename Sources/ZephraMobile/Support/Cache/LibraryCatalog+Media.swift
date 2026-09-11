import Foundation
import ZephraLinkProtocol

/// The bytes behind a picture: its thumbnail, and the whole file.
///
/// Both are the same shape — the store, then the Mac, then the store again — so a picture
/// already looked at costs nothing the second time and a phone with no Mac in reach draws
/// whatever it has already seen. Neither throws for a fetch that simply could not be made: a
/// thumbnail answers nil and a cell shows its placeholder, which is what a grid scrolled past
/// the end of the cache should do.
extension LibraryCatalog {
    /// One picture's thumbnail at one size, from the cache if it is there and from the Mac if
    /// it is not.
    func thumbnail(for entry: CachedEntry, pixels: Int = ThumbnailStore.cellPixels) async -> Data? {
        if let held = await thumbnailStore.data(for: entry, pixels: pixels) { return held }
        guard let client, client.connection.isLive else { return nil }
        do {
            let data = try await client.thumbnail(name: entry.fileName, pixels: pixels)
            await thumbnailStore.store(data, for: entry, pixels: pixels)
            await measureCache()
            return data
        } catch {
            logger.notice("A thumbnail could not be fetched: \(error.localizedDescription)")
            return nil
        }
    }

    /// One picture's file, or a clip's MP4, as a URL on this phone.
    ///
    /// A URL rather than the bytes, because everything that happens to a whole file next wants
    /// one: `ShareLink`, the photo library and `AVPlayer` all take a file, and holding forty
    /// megabytes of clip in memory to hand it to a player that would rather read it is a way
    /// to be killed by the watchdog.
    ///
    /// A clip is two fetches, the poster and the MP4 beside it under the same stem, and it is
    /// the MP4 that comes back — `LibraryItem.exportURL`'s rule, which is the Mac's rule.
    func file(for entry: CachedEntry) async throws -> URL {
        let name = entry.isVideo ? Self.clipName(of: entry.fileName) : entry.fileName
        if let held = await fileStore.url(for: name) { return held }
        guard let client, client.connection.isLive else { throw LibraryCacheError.offline }
        let data = try await client.file(name: name)
        guard let url = await fileStore.store(data, as: name) else {
            throw LibraryCacheError.cannotWrite
        }
        await measureCache()
        return url
    }

    /// The MP4 beside one poster: the same stem, the other extension. `VideoSidecar`'s rule on
    /// the Mac, spelled here because the phone may not import the module it lives in.
    static func clipName(of fileName: String) -> String {
        "\(URL(filePath: fileName).deletingPathExtension().lastPathComponent).mp4"
    }
}

/// What the cache says when it cannot answer.
///
/// Two cases, because a person can act on the difference: one waits for a signal, the other
/// wants room on the phone.
nonisolated enum LibraryCacheError: LocalizedError {
    /// The Mac cannot be reached and the file has never been fetched.
    case offline
    /// The bytes arrived and would not go to disk.
    case cannotWrite

    var errorDescription: String? {
        switch self {
        case .offline: "Your Mac cannot be reached, and this one has not been downloaded yet."
        case .cannotWrite: "There is no room on this phone for that file."
        }
    }
}
