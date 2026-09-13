import Foundation
import ZephraLinkProtocol

extension LibraryCatalog {
    func adoptLegacy(_ remote: [LibraryEntry]) async {
        guard let hostID, let libraryRoot else { return }
        let marker = libraryRoot.appending(path: "legacy-verified")
        guard !FileManager.default.fileExists(atPath: marker.path) else { return }
        let legacyRoot = libraryRoot.deletingLastPathComponent().deletingLastPathComponent().appending(path: "Legacy")
        let legacy = await EntryStore(root: legacyRoot).load()
        let known = Dictionary(remote.map { ($0.fileName, $0) }, uniquingKeysWith: { _, last in last })
        let thumbnails = ThumbnailStore(root: legacyRoot)
        let generation = epoch
        for prior in legacy {
            guard let verified = known[prior.fileName], !prior.isStale(against: verified) else { continue }
            guard generation == epoch, !Task.isCancelled else { return }
            let entry = CachedEntry(verified, hostID: hostID)
            for pixels in [ThumbnailStore.cellPixels, ThumbnailStore.viewerPixels] {
                if let bytes = await thumbnails.data(for: prior, pixels: pixels) {
                    await thumbnailStore.store(bytes, for: entry, pixels: pixels)
                }
            }
            let oldName = prior.isVideo ? Self.clipName(of: prior.fileName) : prior.fileName
            if let bytes = await fileStore.data(for: oldName) {
                let key = mediaKey(entry, fallback: prior.fileName)
                await fileStore.store(bytes, as: prior.isVideo ? Self.clipName(of: key) : key)
            }
        }
        guard generation == epoch, !Task.isCancelled else { return }
        try? Data("verified".utf8).write(to: marker, options: .atomic)
    }
    func stopAndDrain() async {
        let running = observation
        stop()
        await running?.value
        while operations > 0 { try? await Task.sleep(for: .milliseconds(5)) }
    }
}
