import Foundation

/// Favourites and tags: changed on screen at once, written to the files behind them in order.
///
/// Every mutation takes a set of ids, because every one of them is offered on a multiple
/// selection, and a method that took one image would be called in a loop that wrote each file
/// separately.
extension LibraryIndex {
    /// Marks all of `ids` as favourites, or, when they all already are, none of them. Which is
    /// what a single toggle does to a mixed selection: it makes it agree.
    public func toggleFavourite(_ ids: Set<LibraryItem.ID>) {
        let allFavourite = items.filter { ids.contains($0.id) }.allSatisfy(\.isFavourite)
        setFavourite(ids, on: !allFavourite)
    }

    /// Sets or clears the favourite mark on every image in `ids`.
    public func setFavourite(_ ids: Set<LibraryItem.ID>, on isFavourite: Bool) {
        annotate(ids) { $0.isFavourite = isFavourite }
    }

    /// Replaces the tags on every image in `ids`.
    public func setTags(_ tags: [String], on ids: Set<LibraryItem.ID>) {
        let cleaned = Self.cleaned(tags)
        annotate(ids) { $0.tags = cleaned }
    }

    /// Adds one tag to every image in `ids` that has not got it.
    public func addTag(_ tag: String, to ids: Set<LibraryItem.ID>) {
        guard let tag = Self.cleaned([tag]).first else { return }
        annotate(ids) { annotation in
            guard !annotation.tags.contains(tag) else { return }
            annotation.tags.append(tag)
        }
    }

    /// Takes one tag off every image in `ids`.
    public func removeTag(_ tag: String, from ids: Set<LibraryItem.ID>) {
        annotate(ids) { $0.tags.removeAll { $0 == tag } }
    }

    /// Applies a change to the annotation of every image in `ids`, on screen now and on disk
    /// shortly. Images the change leaves alone are not written.
    func annotate(_ ids: Set<LibraryItem.ID>, _ change: (inout LibraryAnnotation) -> Void) {
        var touched = false
        for index in items.indices where ids.contains(items[index].id) {
            var annotation = items[index].annotation
            change(&annotation)
            guard annotation != items[index].annotation else { continue }
            items[index] = items[index].withAnnotation(annotation)
            pending[items[index].id] = annotation
            touched = true
        }
        guard touched else { return }
        reproject()
        enqueue { await self.writePending() }
    }

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
    /// Reverting re-reads the one file rather than remembering what was there: between the
    /// optimistic change and the failure the file may have been changed by something else, and
    /// what is on disk is the only answer that cannot be wrong.
    private func apply(_ write: AnnotationWrite, wrote annotation: LibraryAnnotation?) {
        guard let index = items.firstIndex(where: { $0.id == write.id }) else { return }
        if let modifiedAt = write.modifiedAt, let size = write.size, let annotation {
            items[index] = items[index].written(annotation, modifiedAt: modifiedAt, size: size)
            return
        }
        let url = items[index].url
        guard FileManager.default.fileExists(atPath: write.id) else {
            items.remove(at: index)
            lastFailure = LibraryFailure(
                itemID: write.id, action: .annotate, reason: write.reason ?? "The file is gone.")
            return
        }
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

    /// Tags are trimmed, emptied of blanks, and deduplicated, so "rain " and "rain" are one tag.
    static func cleaned(_ tags: [String]) -> [String] {
        var seen: Set<String> = []
        return tags
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty && seen.insert($0).inserted }
    }
}
