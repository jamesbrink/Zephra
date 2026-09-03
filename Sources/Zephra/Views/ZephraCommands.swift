import SwiftUI
import ZephraEngine

/// The menu bar. Every one of these has a visible twin in the window; the menu exists so the
/// shortcuts are discoverable and so the Mac behaves like a Mac.
struct ZephraCommands: Commands {
    /// The window's store, handed over by the composition root.
    let store: GenerationStore

    var body: some Commands {
        CommandGroup(replacing: .newItem) {
            Button("Generate") { store.generateFromInterface() }
                .keyboardShortcut(.return, modifiers: .command)
                .disabled(!store.canQueue)
            Button("Cancel") { store.cancel() }
                .keyboardShortcut(".", modifiers: .command)
                .disabled(!store.state.isBusy)
        }
        CommandGroup(replacing: .saveItem) {
            Button("Save as…") { if let image = store.current { ImageExport.saveAs(image) } }
                .keyboardShortcut("s", modifiers: .command)
                .disabled(store.current == nil)
            Button("Reveal in Finder") { if let image = store.current { ImageExport.revealInFinder(image) } }
                .keyboardShortcut("r", modifiers: [.command, .shift])
                .disabled(store.current == nil)
            // To the Trash, so it is undoable in the Finder and needs no confirmation here.
            Button("Delete Image", role: .destructive) { if let image = store.current { store.delete(image.id) } }
                .keyboardShortcut(.delete, modifiers: .command)
                .disabled(store.current == nil)
        }
        CommandGroup(after: .pasteboard) {
            Button("Copy Image") { if let image = store.current { ImageExport.copyToPasteboard(image) } }
                .keyboardShortcut("c", modifiers: [.command, .shift])
                .disabled(store.current == nil)
            Divider()
            Button("Use as Reference") { if let image = store.current { store.useAsReference(image.pngData) } }
                .keyboardShortcut("r", modifiers: [.command, .option])
                .disabled(store.current == nil || !store.descriptor.capabilities.supportsReferenceImage)
            Button("Clear Reference") { store.useAsReference(nil) }
                .keyboardShortcut("r", modifiers: [.command, .option, .shift])
                .disabled(store.settings.referenceImage == nil)
        }
    }
}
