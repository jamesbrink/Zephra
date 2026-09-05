import Foundation
import ZephraEngine

extension AppSettings {
    /// Saving and indexing read the same preference at launch. This app is not sandboxed,
    /// so the selected path needs no security-scoped bookmark.
    static func imageLibrary() -> ImageLibrary {
        let stored = UserDefaults.standard.string(forKey: imagesDirectory) ?? ""
        return stored.isEmpty ? .pictures() : ImageLibrary(root: URL(filePath: stored, directoryHint: .isDirectory))
    }

    /// Called only after the engine has successfully changed both the writer and the index.
    static func recordImagesDirectory(_ folder: URL?) {
        UserDefaults.standard.set(folder?.path(percentEncoded: false) ?? "", forKey: imagesDirectory)
    }
}
