import SwiftUI
import ZephraEngine

/// The Model menu: get the weights in, give them back, or go looking for another model.
///
/// Its own top-level menu rather than three more items in File. File's group is Generate, Stop
/// and New Album — the things a person makes — and these three are about the engine that makes
/// them and about what is on the disk. Putting Load Model directly under Generate would also
/// sit the two items that now interact ("Generate loads it first") side by side, where they
/// read as alternatives.
///
/// Every item here has a visible twin in the window — `ModelLoadButton` and the pull-down's
/// More Models… — and reads the same two answers it does, so a greyed item and a greyed button
/// cannot disagree.
struct ModelCommands: Commands {
    /// The window's store, handed over by the composition root.
    let store: GenerationStore
    /// The window's selection, which owns the browser's flag.
    let workspace: WorkspaceSelection
    /// Whether the first-launch chooser is up. The browser is a sheet on `RootView`, which is
    /// not in the hierarchy at all while the chooser is: setting the flag there would raise the
    /// browser the moment the chooser went, over a window the person had not yet seen.
    let welcome: WelcomeGate

    var body: some Commands {
        CommandMenu("Model") {
            Button("Load Model") { store.loadModel() }
                .keyboardShortcut("l", modifiers: [.command, .option])
                .disabled(!store.canLoad(store.descriptor))
            Button("Unload Model") { store.unloadModel() }
                .keyboardShortcut("l", modifiers: [.command, .option, .shift])
                .disabled(!store.canUnload)
            Divider()
            Button("More Models\u{2026}") { workspace.showsModelBrowser = true }
                .keyboardShortcut("m", modifiers: [.command, .shift])
                // Out while the chooser is up, and out while the reference picker is: both are
                // sheets on the one window, and a sheet raised over a sheet stacks.
                .disabled(welcome.isShowing || workspace.showsReferencePicker)
        }
    }
}
