import SwiftUI

/// The menu bar's half of the window's navigation: the two panes, the search field, the
/// inspector, and the strip of this run's images.
///
/// Every one of these has a visible twin in the window. The menu exists so the shortcuts are
/// discoverable and so the Mac behaves like a Mac.
struct WorkspaceCommands: Commands {
    /// The window's selection, handed over by the composition root.
    let workspace: WorkspaceSelection

    @AppStorage(AppSettings.runStripVisible)
    private var runStripVisible = AppSettings.initialRunStripVisible

    var body: some Commands {
        CommandGroup(after: .toolbar) {
            Button("Canvas") { workspace.pane = .canvas }
                .keyboardShortcut("1", modifiers: .command)
            Button("Library") { workspace.pane = .library }
                .keyboardShortcut("2", modifiers: .command)
            Divider()
            Toggle("Show This Run", isOn: $runStripVisible)
                .keyboardShortcut("r", modifiers: [.option, .command])
            Button("Show Inspector") { workspace.inspectorVisible.toggle() }
                .keyboardShortcut("i", modifiers: [.option, .command])
                .disabled(workspace.pane != .library)
            Divider()
        }
        CommandGroup(after: .textEditing) {
            Button("Find") { workspace.focusSearch() }
                .keyboardShortcut("f", modifiers: .command)
        }
    }
}
