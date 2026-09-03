import SwiftUI

/// Shows or hides the facts beside the grid or the canvas.
struct InspectorToggle: View {
    @Environment(WorkspaceSelection.self) private var workspace

    var body: some View {
        Button {
            workspace.inspectorVisible.toggle()
        } label: {
            Label("Inspector", systemImage: "sidebar.trailing")
                .symbolVariant(workspace.inspectorVisible ? .fill : .none)
        }
        // ⌥⌘I belongs to WorkspaceCommands. A shortcut declared in two places is one
        // stray SwiftUI change away from toggling twice.
        .help(workspace.inspectorVisible ? "Hide the inspector" : "Show the inspector")
    }
}

#Preview("Inspector") {
    InspectorToggle()
        .padding()
        .environment(WorkspaceSelection(pane: .library))
}
