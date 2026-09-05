import Foundation

/// The write chain under every mutation: one pass per batch of pending annotations, off the
/// main actor, and what happens to the index when a write lands or does not.
extension LibraryIndex {
    /// Writes everything queued, in one pass off the main actor.
    func writePending() async {
        guard !pending.isEmpty else { return }
        let batch = pending
        pending = [:]
        let library = library
        let results = await Task.detached(priority: .utility) { () -> [AnnotationWrite] in
            batch.map { id, annotation in
                do {
                    let written = try library.annotate(URL(filePath: id), with: annotation)
                    return AnnotationWrite(
                        id: id, modifiedAt: written.modifiedAt, size: written.size, reason: nil)
                } catch {
                    return AnnotationWrite(
                        id: id, modifiedAt: nil, size: nil, reason: error.localizedDescription)
                }
            }
        }.value
        for result in results { apply(result, wrote: batch[result.id]) }
        reproject()
    }

    /// What one attempted write came back with.
    struct AnnotationWrite: Sendable {
        let id: LibraryItem.ID
        let modifiedAt: Date?
        let size: Int64?
        let reason: String?
    }

    /// Records a write that landed, or puts one that did not back to what the file says.
    ///
    /// A newer change may be waiting in `pending` behind this write; then what is on screen is
    /// the newer value and this write must not put the older one back, nor revert or report:
    /// the newer write is about to land and will speak for itself.
    ///
    /// Reverting re-reads the one file rather than remembering what was there: between the
    /// optimistic change and the failure the file may have been changed by something else, and
    /// what is on disk is the only answer that cannot be wrong.
    func apply(_ write: AnnotationWrite, wrote annotation: LibraryAnnotation?) {
        guard let index = items.firstIndex(where: { $0.id == write.id }) else { return }
        let newerWaiting = pending[write.id] != nil
        if let modifiedAt = write.modifiedAt, let size = write.size, let annotation {
            // Record what the file now looks like so the next scan recognises it, keeping the
            // annotation on screen when a newer one is queued behind this write.
            let shown = newerWaiting ? items[index].annotation : annotation
            items[index] = items[index].written(shown, modifiedAt: modifiedAt, size: size)
            return
        }
        let url = items[index].url
        guard FileManager.default.fileExists(atPath: write.id) else {
            items.remove(at: index)
            lastFailure = LibraryFailure(
                itemID: write.id, action: .annotate, reason: write.reason ?? "The file is gone.")
            return
        }
        guard !newerWaiting else { return }
        items[index] = items[index].withAnnotation(library.annotation(at: url))
        lastFailure = LibraryFailure(
            itemID: write.id, action: .annotate, reason: write.reason ?? "The write did not land.")
    }

    /// Queues work behind whatever the library is already doing, so two mutations never write
    /// the same file at once and a rescan never runs against a half-finished write.
    func enqueue(_ operation: @escaping @MainActor () async -> Void) {
        let previous = work
        work = Task { @MainActor in
            await previous?.value
            await operation()
        }
    }
}
