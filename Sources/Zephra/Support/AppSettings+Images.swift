import Foundation
import ZephraEngine

extension AppSettings {
    /// Saving and indexing read the same preference at launch. This app is not sandboxed,
    /// so the selected path needs no security-scoped bookmark.
    static func imageLibrary() -> ImageLibrary {
        let stored = store.string(forKey: imagesDirectory) ?? ""
        guard stored.isEmpty else {
            return ImageLibrary(root: URL(filePath: stored, directoryHint: .isDirectory))
        }
        // `~/Pictures/Zephra`, or the fresh start's own folder when this launch is pretending
        // to be a new Mac.
        return FreshStart.current.map { ImageLibrary(root: $0.images) } ?? .pictures()
    }

    /// Called only after the engine has successfully changed both the writer and the index.
    static func recordImagesDirectory(_ folder: URL?) {
        store.set(folder?.path(percentEncoded: false) ?? "", forKey: imagesDirectory)
    }
}
