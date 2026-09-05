import Foundation

/// Undo for what a person changes about a picture afterwards: favourites, tags and album
/// membership, which are the one annotation chunk.
///
/// The index registers the inverse itself rather than the call sites, because at the moment of
/// a change it is the only thing that still knows the previous value of every image touched.
/// Undoing is an ordinary `annotate` back to those values, and `annotate` records what it
/// changed, which is how an undo registers its own redo without a second path.
///
/// Deleting stays out: Recently Deleted keeps a picture for thirty days, which is the recovery
/// a delete wants, and Put Back is where it lives.
extension LibraryIndex {
    /// Registers putting `previous` back, under `name` on the Edit menu. Nothing is registered
    /// for an empty set, so a change that touched no image leaves no "Undo" that does nothing.
    func recordUndo(restoring previous: [LibraryItem.ID: LibraryAnnotation], named name: String) {
        guard !previous.isEmpty else { return }
        recordUndo(named: name) { index in index.restoreAnnotations(previous, named: name) }
    }

    /// Registers `inverse` on the manager, if there is one, and names the menu item after it.
    func recordUndo(named name: String, _ inverse: @escaping @MainActor (LibraryIndex) -> Void) {
        guard let undoManager else { return }
        undoManager.registerUndo(withTarget: self, handler: inverse)
        undoManager.setActionName(name)
    }

    /// Puts every image in `previous` back to the annotation it had. Going through `annotate`
    /// is what registers the redo: the manager is undoing, so the registration lands on the
    /// redo stack.
    func restoreAnnotations(_ previous: [LibraryItem.ID: LibraryAnnotation], named name: String) {
        annotate(Set(previous.keys), named: name) { id, annotation in
            if let restored = previous[id] { annotation = restored }
        }
    }
}
