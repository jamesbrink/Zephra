import Foundation
import ZephraLinkProtocol

/// The bytes behind a picture: its thumbnail, and the whole file.
///
/// Both are the same shape — the store, then the Mac, then the store — so a picture already
/// looked at costs nothing the second time and a phone with no Mac in reach draws whatever it
/// has already seen. This is the **one** door whole files and thumbnails cross the link
/// through, for the canvas as much as for the library: a picture fetched on either surface is
/// on the phone for the other, and it crosses what may be a relay once.
///
/// Neither throws for a fetch that simply could not be made: a thumbnail answers nil and a cell
/// shows its placeholder, which is what a grid scrolled past the end of the cache should do.
extension LibraryCatalog {
    /// One picture's thumbnail at one size, from the cache if it is there and from the Mac if
    /// it is not.
    func thumbnail(for entry: CachedEntry, pixels: Int = ThumbnailStore.cellPixels) async -> Data? {
        if let child = owner(of: entry) { return await child.thumbnail(for: entry, pixels: pixels) }
        operations += 1
        defer { operations -= 1 }
        let generation = epoch
        if let held = await thumbnailStore.data(for: entry, pixels: pixels) { return held }
        guard let client, client.connection.isLive else { return nil }
        do {
            let data = try await client.thumbnail(name: entry.fileName, pixels: pixels)
            guard generation == epoch else { return nil }
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
    func file(for entry: CachedEntry) async throws -> URL {
        if let child = owner(of: entry) { return try await child.file(for: entry) }
        return try await url(named: entry.id, isVideo: entry.isVideo)
    }

    /// One file, asked for by the name the Mac knows it by and kept under the name this phone
    /// files it under.
    ///
    /// **Those are two different names for a clip**, and it matters. The Mac's index is its
    /// pictures: it resolves a poster's name and nothing else, so a request naming the MP4 is
    /// a picture the Mac has never heard of and comes back `notFound`. What arrives is the MP4
    /// all the same — `Command.fetchFile` answers a clip's video for its poster — and that is
    /// what lands beside the poster under the same stem, which is `VideoSidecar`'s rule and the
    /// rule `hasFile(for:)` reads back.
    func url(named name: String, isVideo: Bool) async throws -> URL {
        if let entry = entry(named: name), let child = owner(of: entry) {
            return try await child.url(named: entry.id, isVideo: isVideo)
        }
        let entry = entry(named: name)
        let remote = entry?.fileName ?? name
        let key = mediaKey(entry, fallback: name)
        let local = isVideo ? Self.clipName(of: key) : key
        operations += 1
        defer { operations -= 1 }
        let generation = epoch
        if let held = await fileStore.url(for: local) { return held }
        guard let client, client.connection.isLive else { throw LibraryCacheError.offline }
        let data = try await client.file(name: remote)
        guard generation == epoch else { throw CancellationError() }
        guard let url = await fileStore.store(data, as: local) else {
            throw LibraryCacheError.cannotWrite
        }
        await measureCache()
        return url
    }

    /// One picture's bytes by name: the store, then the Mac, then the store.
    ///
    /// The bytes rather than the URL, for the two callers that want a picture and not a file —
    /// the canvas, which decodes one, and the reference well, which sends one back. Nil rather
    /// than a throw, because both draw the same rectangle either way and neither has anywhere
    /// to put a sentence.
    func picture(named name: String) async -> Data? {
        if let entry = entry(named: name), let child = owner(of: entry) { return await child.picture(named: entry.id) }
        let entry = entry(named: name)
        let remote = entry?.fileName ?? name
        let key = mediaKey(entry, fallback: name)
        operations += 1
        defer { operations -= 1 }
        let generation = epoch
        if let held = await fileStore.data(for: key) { return held }
        guard let client, client.connection.isLive else { return nil }
        guard let data = try? await client.file(name: remote) else {
            logger.notice("A picture could not be fetched from the Mac")
            return nil
        }
        guard generation == epoch else { return nil }
        await fileStore.store(data, as: key)
        await measureCache()
        return data
    }

    /// Whether one picture's file is already on this phone.
    ///
    /// What Save to Photos and Share are greyed by while the Mac is out of reach: both work
    /// offline for a file already fetched — you save the one you have been looking at — and
    /// neither can do anything for one that was never fetched.
    func hasFile(for entry: CachedEntry) async -> Bool {
        if let child = owner(of: entry) { return await child.hasFile(for: entry) }
        let key = mediaKey(entry, fallback: entry.fileName)
        let name = entry.isVideo ? Self.clipName(of: key) : key
        return await fileStore.url(for: name) != nil
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
