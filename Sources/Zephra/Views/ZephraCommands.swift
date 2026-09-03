import SwiftUI
import ZephraEngine

/// The menu bar. Every one of these has a visible twin in the window; the menu exists so the
/// shortcuts are discoverable and so the Mac behaves like a Mac.
///
/// Save as, Copy, Reveal and Delete mean two different things depending on where you are
/// standing, so each of them asks `target` rather than reaching for the canvas: the library's
/// selection while the grid has the keyboard, and the image on the canvas otherwise. The grid's
/// focus rather than the library pane's presence, because ⌘⌫ in a text field means the line and
/// a scene-wide binding would take that away.
struct ZephraCommands: Commands {
    /// The window's store, handed over by the composition root.
    let store: GenerationStore

    /// The grid's selection while it has the keyboard. Not private: `ZephraCommands+Library`
    /// is where the four file commands work out what they are about.
    @FocusedValue(\.focusedLibraryGrid) var grid
    /// The library behind that selection.
    @FocusedValue(\.libraryIndex) var libraryIndex
    /// Making an album, published by the sidebar while the library pane is up. An action rather
    /// than a piece of state because naming the new album happens in `SidebarView`'s own state,
    /// which nothing out here can reach; nil is what greys the item out on the canvas.
    @FocusedValue(\.newAlbum) var newAlbum

    var body: some Commands {
        CommandGroup(replacing: .newItem) {
            Button("Generate") { store.generateFromInterface() }
                .keyboardShortcut(.return, modifiers: .command)
                .disabled(!store.canQueue)
            Button("Cancel") { store.cancel() }
                .keyboardShortcut(".", modifiers: .command)
                .disabled(!store.state.isBusy)
            Divider()
            Button("New Album") { newAlbum?() }
                .keyboardShortcut("n", modifiers: .command)
                .disabled(newAlbum == nil)
        }
        CommandGroup(replacing: .saveItem) {
            Button(target.saveTitle) { save() }
                .keyboardShortcut("s", modifiers: .command)
                .disabled(target.isEmpty)
            Button("Reveal in Finder") { reveal() }
                .keyboardShortcut("r", modifiers: [.command, .shift])
                .disabled(target.isEmpty)
            Button(target.deleteTitle, role: .destructive) { delete() }
                .keyboardShortcut(.delete, modifiers: .command)
                .disabled(target.isEmpty)
        }
        CommandGroup(after: .pasteboard) {
            Button(target.copyTitle) { copy() }
                .keyboardShortcut("c", modifiers: [.command, .shift])
                .disabled(target.isEmpty)
            Divider()
            Button("Use as Reference") { if let image = store.current { store.useAsReference(image.pngData) } }
                .keyboardShortcut("r", modifiers: [.command, .option])
                .disabled(store.current == nil || !store.descriptor.capabilities.supportsReferenceImage)
            Button("Clear Reference") { store.useAsReference(nil) }
                .keyboardShortcut("r", modifiers: [.command, .option, .shift])
                .disabled(store.settings.referenceImage == nil)
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
