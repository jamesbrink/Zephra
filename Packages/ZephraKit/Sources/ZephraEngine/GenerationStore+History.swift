import Foundation
import ZephraCore

/// This session's filmstrip, and taking an image out of it. Split out of
/// `GenerationStore.swift` so the observed surface of the store stays readable on its own.
///
/// Nothing is read back at launch any more: the folder is the library's business, and
/// `LibraryIndex` reads it. What is here is what this session made.
extension GenerationStore {
    /// Takes an image out of the filmstrip and moves its file into Recently Deleted.
    ///
    /// Nothing is asked first: the image waits thirty days in a folder inside the library, which
    /// is exactly why it is moved rather than deleted. That is also the one place a delete can
    /// go — the library pane deletes into the same folder, and two paths, one to the Finder's
    /// Trash and one to Recently Deleted, would mean a delete meant different things depending
    /// on where it was made. Deleting the image on the canvas shows the next newest one instead,
    /// without adopting its settings, so a prompt being edited survives it.
    public func delete(_ id: GeneratedImage.ID) {
        let index = history.firstIndex { $0.id == id }
        let removed = index.map { history[$0] } ?? (current?.id == id ? current : nil)
        guard let removed else { return }
        if let index { history.remove(at: index) }
        if current?.id == id { current = next(after: index) }
        guard let url = removed.fileURL else { return }
        let library = library
        let previous = libraryTask
        libraryTask = Task.detached(priority: .utility) {
            await previous?.value
            do {
                try library.moveToRecentlyDeleted(url)
                await MainActor.run { self.onImageDeleted?(url) }
            } catch {
                let reason = error.localizedDescription
                await MainActor.run { self.discardFailed(url, reason) }
            }
        }
    }

    /// What to show after the image at `index` is gone: the one that took its place, or the
    /// oldest left, or nothing at all.
    private func next(after index: Int?) -> GeneratedImage? {
        guard let index else { return history.first }
        return history.indices.contains(index) ? history[index] : history.last
    }

    /// A file that could not be moved is logged and otherwise let be. The image is already out
    /// of the filmstrip, and there is nothing the person using the app can do about a locked
    /// file from in here.
    private func discardFailed(_ url: URL, _ reason: String) {
        logger.error(
            "could not delete \(url.lastPathComponent, privacy: .public): \(reason, privacy: .public)"
        )
    }
}
