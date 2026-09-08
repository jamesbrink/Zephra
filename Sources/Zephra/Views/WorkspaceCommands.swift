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
            //
            // A button whose title alternates rather than a checked toggle: the prompt is not a
            // piece of chrome you keep switched on, it is either in the way or it is not, and
            // "Hide Prompt" with a tick beside it reads as the wrong sentence for a prompt that
            // is already hidden. The Mac's own wording for this is the alternation.
            Button(workspace.promptTucked ? "Show Prompt" : "Hide Prompt") {
                workspace.promptTucked.toggle()
            }
            .keyboardShortcut("p", modifiers: [.option, .command])
            .disabled(workspace.pane != .canvas)
            Divider()
        }
        CommandGroup(after: .textEditing) {
            // Edit > Find > Find…, where every Mac keeps it. A `Menu` inside the group is what
            // draws a submenu; `CommandMenu` would put Find in the menu bar beside Edit rather
            // than inside it, and SwiftUI publishes no `.find` placement of its own to insert
            // into. One item in the submenu for now — Find Next and Use Selection for Find have
            // nothing to do here — but the shape is the one a person reaches into.
            Menu("Find") {
                Button("Find…") { workspace.focusSearch() }
                    .keyboardShortcut("f", modifiers: .command)
            }
        }
    }

    /// `workspace` arrives as a plain reference rather than `@Bindable`, since `Commands` has no
    /// view body of its own to project one from — so the one toggle left gets its binding
    /// written by hand.
    private var inspectorVisible: Binding<Bool> {
        Binding(
            get: { workspace.inspectorVisible },
            set: { workspace.inspectorVisible = $0 }
        )
    }
}
