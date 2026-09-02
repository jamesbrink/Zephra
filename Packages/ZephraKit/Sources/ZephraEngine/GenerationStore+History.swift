import Foundation
import ZephraCore

/// History that outlives the session that made it: the filmstrip refilled from the library at
/// launch, and images taken back out of it again. Split out of `GenerationStore.swift` so the
/// observed surface of the store stays readable on its own.
extension GenerationStore {
    /// Reads the newest images in the library back into `history`, in the background.
    ///
    /// Called once, from the initializer rather than from `bootstrap()`, so it never delays the
    /// model: reading a couple of dozen PNGs is nothing next to loading weights, and the
    /// filmstrip filling in while the model is still arriving is the point of it. A preview
    /// store has no registry and reads nothing, so a screenshot build never touches the folder.
    ///
    /// It shares `libraryTask` with deletion, so the two never touch the folder at once.
    func startRestore() {
        guard registry != nil else { return }
        let library = library
        let limit = Self.historyLimit
        let cutoff = Date()
        libraryTask = Task.detached(priority: .utility) {
            let restored = library.restore(limit: limit)
            await MainActor.run { self.adopt(restored, madeBefore: cutoff) }
        }
    }

    /// Merges what was on disk into whatever this session has made in the meantime.
    ///
    /// Restored images go after anything generated while the read was running, so the
    /// newest-first order holds however the two race. `current` is filled in only when nothing
    /// has claimed it, and `settings` is left alone: the prompt in the field belongs to this
    /// session, not the last one.
    ///
    /// The library is taken as it stood when the store was made: an image this session wrote
    /// while the read was in flight is already in `history`, and `madeBefore` keeps it from
    /// arriving a second time under a second identity.
    private func adopt(_ restored: [GeneratedImage], madeBefore cutoff: Date) {
        let known = Set(history.compactMap { $0.fileURL?.standardizedFileURL })
        let additions = restored.filter { image in
            guard image.createdAt < cutoff else { return false }
            return image.fileURL.map { !known.contains($0.standardizedFileURL) } ?? true
        }
        guard !additions.isEmpty else { return }
        history = Array((history + additions).prefix(Self.historyLimit))
        if current == nil { current = history.first }
        logger.info("restored \(additions.count) image(s) from the library")
    }

    /// Takes an image out of the filmstrip and moves its file to the Trash.
    ///
    /// Nothing is asked first: the file is recoverable from the Finder, which is exactly why it
    /// is trashed rather than deleted. Deleting the image on the canvas shows the next newest
    /// one instead, without adopting its settings, so a prompt being edited survives it.
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
                try library.discard(url)
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

    /// A file that could not be trashed is logged and otherwise let be. The image is already
    /// out of the filmstrip, and there is nothing the person using the app can do about a
    /// locked file from in here.
    private func discardFailed(_ url: URL, _ reason: String) {
        logger.error(
            "could not trash \(url.lastPathComponent, privacy: .public): \(reason, privacy: .public)"
        )
    }
}
