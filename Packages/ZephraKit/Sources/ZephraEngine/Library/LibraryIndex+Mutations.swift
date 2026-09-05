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
        annotate(ids, named: "Favorite") { $1.isFavourite = isFavourite }
    }

    /// Replaces the tags on every image in `ids`.
    public func setTags(_ tags: [String], on ids: Set<LibraryItem.ID>) {
        let cleaned = Self.cleaned(tags)
        annotate(ids, named: "Tag") { $1.tags = cleaned }
    }

    /// Adds one tag to every image in `ids` that has not got it.
    public func addTag(_ tag: String, to ids: Set<LibraryItem.ID>) {
        guard let tag = Self.cleaned([tag]).first else { return }
        annotate(ids, named: "Tag") { _, annotation in
            guard !annotation.tags.contains(tag) else { return }
            annotation.tags.append(tag)
        }
    }

    /// Takes one tag off every image in `ids`.
    public func removeTag(_ tag: String, from ids: Set<LibraryItem.ID>) {
        annotate(ids, named: "Tag") { $1.tags.removeAll { $0 == tag } }
    }

    /// Applies a change to the annotation of every image in `ids`, on screen now and on disk
    /// shortly, and registers its inverse under `name` on the Edit menu. Images the change
    /// leaves alone are neither written nor remembered.
    func annotate(
        _ ids: Set<LibraryItem.ID>,
        named name: String,
        _ change: (LibraryItem.ID, inout LibraryAnnotation) -> Void
    ) {
        recordUndo(restoring: applyAnnotations(ids, change), named: name)
    }

    /// The mutation under `annotate`, without the undo: what each touched image's annotation
    /// was before, keyed by id, so the caller can register putting it back — or fold it into a
    /// larger inverse of its own, as deleting an album does.
    func applyAnnotations(
        _ ids: Set<LibraryItem.ID>,
        _ change: (LibraryItem.ID, inout LibraryAnnotation) -> Void
    ) -> [LibraryItem.ID: LibraryAnnotation] {
        guard !isChangingDirectory else { return [:] }
        var previous: [LibraryItem.ID: LibraryAnnotation] = [:]
        for index in items.indices where ids.contains(items[index].id) {
            var annotation = items[index].annotation
            change(items[index].id, &annotation)
            guard annotation != items[index].annotation else { continue }
            previous[items[index].id] = items[index].annotation
            items[index] = items[index].withAnnotation(annotation)
            pending[items[index].id] = annotation
        }
        guard !previous.isEmpty else { return [:] }
        reproject()
        enqueue { await self.writePending() }
        return previous
    }

    /// Tags are trimmed, emptied of blanks, and deduplicated, so "rain " and "rain" are one tag.
    static func cleaned(_ tags: [String]) -> [String] {
        var seen: Set<String> = []
        return tags
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty && seen.insert($0).inserted }
    }
}
