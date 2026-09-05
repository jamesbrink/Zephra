import SwiftUI
import ZephraEngine

/// Hands the window's undo manager to the library index, so a favourite, a tag or an album
/// edit made anywhere in the window answers to the Edit menu's Undo and Redo.
///
/// A modifier rather than a line in `RootView`, whose three stored properties are spoken for.
/// The environment's manager is the window's own — the one the standard Undo and Redo items
/// send to whenever a text field is not first responder, since a field's typing has a manager
/// of its own and should keep it. No `CommandGroup` replaces `.undoRedo`; that is what lets
/// the standard items reach it.
struct LibraryUndoRegistration: ViewModifier {
    @Environment(\.undoManager) private var undoManager
    @Environment(LibraryIndex.self) private var index

    func body(content: Content) -> some View {
        content.onChange(of: undoManager, initial: true) { _, manager in
            index.undoManager = manager
        }
    }
}

extension View {
    /// Registers this window's undo manager with the library index. See
    /// `LibraryUndoRegistration`.
    func registeringLibraryUndo() -> some View {
        modifier(LibraryUndoRegistration())
    }
}
