import SwiftUI
import ZephraEngine

/// The menu bar's half of the window's navigation: the two panes, the search field, the
/// inspector, and the canvas's tucked-away prompt.
///
/// Every one of these has a visible twin in the window. The menu exists so the shortcuts are
/// discoverable and so the Mac behaves like a Mac.
struct WorkspaceCommands: Commands {
    /// The window's selection, handed over by the composition root.
    let workspace: WorkspaceSelection
    /// The engine, for the one command that depends on whether the canvas has a picture.
    let store: GenerationStore

    var body: some Commands {
        CommandGroup(after: .toolbar) {
            Button("Canvas") { workspace.pane = .canvas }
                .keyboardShortcut("1", modifiers: .command)
            Button("Library") { workspace.pane = .library }
                .keyboardShortcut("2", modifiers: .command)
            Divider()
            Toggle("Show Inspector", isOn: inspectorVisible)
                .keyboardShortcut("i", modifiers: [.option, .command])
                // The same rule as the toolbar's toggle: a canvas with nothing on it has
                // nothing to inspect, and the menu says so by being grey.
                .disabled(workspace.pane == .canvas && !store.hasPicture)
            // Escape and typing also bring the prompt back, through `PromptTuckHost`; this is
            // the discoverable, menu-bar way to do the same thing `WorkspaceCommands`' doc
            // comment promises for everything else here.
            Toggle("Hide Prompt", isOn: promptTucked)
                .keyboardShortcut("p", modifiers: [.option, .command])
                .disabled(workspace.pane != .canvas)
            Divider()
        }
        CommandGroup(after: .textEditing) {
            Button("Find") { workspace.focusSearch() }
                .keyboardShortcut("f", modifiers: .command)
        }
    }

    /// `workspace` arrives as a plain reference rather than `@Bindable`, since `Commands` has no
    /// view body of its own to project one from — so the toggles get bindings written by hand.
    private var inspectorVisible: Binding<Bool> {
        Binding(
            get: { workspace.inspectorVisible },
            set: { workspace.inspectorVisible = $0 }
        )
    }

    private var promptTucked: Binding<Bool> {
        Binding(
            get: { workspace.promptTucked },
            set: { workspace.promptTucked = $0 }
        )
    }
}
