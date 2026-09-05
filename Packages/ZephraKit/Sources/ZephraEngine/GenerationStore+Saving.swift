import Foundation
import ZephraCore

/// Getting a finished image onto disk, on one serial chain, and what the store learns when
/// the write lands or fails.
extension GenerationStore {
    func save(_ image: GeneratedImage) {
        let library = library
        let previous = saveTask
        saveTask = Task.detached(priority: .utility) { [image] in
            await previous?.value
            do {
                let url = try library.write(image)
                await MainActor.run { self.attach(url, to: image.id) }
            } catch {
                let failure = SaveFailure(imageID: image.id, reason: error.localizedDescription)
                await MainActor.run { self.saveFailed(failure) }
            }
        }
    }

    /// Records where the image landed. One deleted while its write was in flight goes straight
    /// on to Recently Deleted instead, and never reaches `onImageSaved`: the index learns of
    /// it as a delete, and a picture the user removed does not reappear in the library.
    func attach(_ url: URL, to id: GeneratedImage.ID) {
        lastSaveFailure = nil
        if deletedBeforeSave.remove(id) != nil {
            moveToRecentlyDeleted(url)
            return
        }
        if current?.id == id {
            current = current?.withFileURL(url)
        }
        if let index = history.firstIndex(where: { $0.id == id }) {
            history[index] = history[index].withFileURL(url)
        }
        onImageSaved?(url)
    }

    /// A failed write is worth showing, but the pixels are still in memory and still on the
    /// canvas, so `current` and `history` are left exactly as they were.
    ///
    /// It does not become an engine state either. A save lands after `finish()` has already
    /// started the next queued generation, so failing the engine here would stop a queue over
    /// a full disk, and the remedy on the failure screen reloads the model, which would be no
    /// remedy at all. The interface shows this as a notice until an image saves cleanly.
    func saveFailed(_ failure: SaveFailure) {
        // Nothing landed, so there is nothing to move on.
        deletedBeforeSave.remove(failure.imageID)
        logger.error("save failed: \(failure.reason, privacy: .public)")
        lastSaveFailure = failure
    }
}
