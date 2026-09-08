import SwiftUI
import ZephraEngine

/// The menu bar. Every one of these has a visible twin in the window; the menu exists so the
/// shortcuts are discoverable and so the Mac behaves like a Mac.
///
/// Export, Share, Copy, Reveal, Delete, Use as Reference, Animate and Upscale mean different
/// things depending on where you are standing, so each of them asks `target` (a `CommandTarget`)
/// rather than reaching for the canvas: the grid's selection while the grid has the keyboard,
/// the canvas's picture while the canvas is showing one, and nothing otherwise. The grid's focus rather than
/// the library pane's presence, because ⌘⌫ in a text field means the line and a scene-wide
/// binding would take that away; and nothing rather than the canvas behind the library, because
/// a command that acted on a picture nobody can see would be acting on a guess.
struct ZephraCommands: Commands {
    /// The window's store, handed over by the composition root.
    let store: GenerationStore
    /// The window's selection, handed over the same way: which pane is up decides what the
    /// file commands are about.
    let workspace: WorkspaceSelection

    /// The grid's selection while it has the keyboard. Not private: `ZephraCommands+Library`
    /// is where the four file commands work out what they are about.
    @FocusedValue(\.focusedLibraryGrid) var grid
    /// The library behind that selection.
    @FocusedValue(\.libraryIndex) var libraryIndex
    /// Whether the canvas's prompt has the keyboard. Only the deletion reads it, through
    /// `deleteTarget`: ⌘⌫ there means the line under the caret.
    @FocusedValue(\.promptHasKeyboard) var promptHasKeyboard
    /// Making an album, published by the sidebar while the library pane is up. An action rather
    /// than a piece of state because naming the new album happens in `SidebarView`'s own state,
    /// which nothing out here can reach; nil is what greys the item out on the canvas.
    @FocusedValue(\.newAlbum) var newAlbum

    var body: some Commands {
        CommandGroup(replacing: .newItem) {
            Button("Generate") { store.generateFromInterface() }
                .keyboardShortcut(.return, modifiers: .command)
                .disabled(!store.canQueue)
            Button(store.state.stopCommandTitle) { store.cancel() }
                .keyboardShortcut(".", modifiers: .command)
                .disabled(!store.state.isBusy)
            Divider()
            Button("New Album") { newAlbum?() }
                .keyboardShortcut("n", modifiers: .command)
                .disabled(newAlbum == nil)
        }
        CommandGroup(replacing: .saveItem) {
            // ⇧⌘E rather than ⌘S: nothing here is a document with unsaved changes, and a
            // picture is already on the disk. What this does is copy it somewhere else.
            Button(target.exportTitle) { save() }
                .keyboardShortcut("e", modifiers: [.command, .shift])
                .disabled(target.isEmpty)
            Button("Reveal in Finder") { reveal() }
                .keyboardShortcut("r", modifiers: [.command, .shift])
                .disabled(target.isEmpty)
            Button(target.shareTitle) { share() }
                .disabled(shareFiles.isEmpty)
            // `deleteTarget` rather than `target`: this is the one item here whose shortcut a
            // text view already means something by, and a bound key equivalent is matched before
            // the responder chain, so the item stands down while the prompt has the caret.
            Button(deleteTarget.deleteTitle, role: .destructive) { delete() }
                .keyboardShortcut(.delete, modifiers: .command)
                .disabled(deleteTarget.isEmpty)
        }
        CommandGroup(after: .pasteboard) {
            Button(target.copyTitle) { copy() }
                .keyboardShortcut("c", modifiers: [.command, .shift])
                .disabled(target.isEmpty)
            Divider()
            Button("Use as Reference") { useAsReference() }
                .keyboardShortcut("r", modifiers: [.command, .option])
                .disabled(!canUseAsReference)
            Button("Clear Reference") { ReferenceAdoption.use(nil, into: store) }
                .keyboardShortcut("r", modifiers: [.command, .option, .shift])
                .disabled(store.settings.referenceImage == nil)
            Button(target.animateTitle) { animate() }
                .keyboardShortcut("a", modifiers: [.command, .option])
                .disabled(!canAnimateTarget)
            Divider()
            Button("Upscale 2\u{00D7}") { upscale(2) }
                .keyboardShortcut("u", modifiers: [.command, .option])
                .disabled(upscaleSource == nil || !store.canUpscale)
            Button("Upscale 4\u{00D7}") { upscale(4) }
                .keyboardShortcut("u", modifiers: [.command, .option, .shift])
                .disabled(upscaleSource == nil || !store.canUpscale)
        }
    }
}
