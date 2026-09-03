import SwiftUI
import ZephraEngine

/// Shows or hides the facts beside the grid or the canvas. Greyed on a canvas with nothing on
/// it, because there is nothing for the column to describe there and `WorkspaceDetail` would
/// not show it anyway.
struct InspectorToggle: View {
    @Environment(WorkspaceSelection.self) private var workspace
    @Environment(GenerationStore.self) private var store

    var body: some View {
        Button {
            workspace.inspectorVisible.toggle()
        } label: {
            Label("Inspector", systemImage: "sidebar.trailing")
                .symbolVariant(workspace.inspectorVisible ? .fill : .none)
        }
        // ⌥⌘I belongs to WorkspaceCommands. A shortcut declared in two places is one
        // stray SwiftUI change away from toggling twice.
        .disabled(nothingToInspect)
        .help(help)
    }

    private var nothingToInspect: Bool {
        workspace.pane == .canvas && !store.hasPicture
    }

    private var help: String {
        if nothingToInspect { return "Nothing on the canvas to inspect" }
        return workspace.inspectorVisible ? "Hide the inspector" : "Show the inspector"
    }
}

#Preview("Inspector") {
    InspectorToggle()
        .padding()
        .environment(WorkspaceSelection(pane: .library))
        .environment(GenerationStore.preview(state: .ready))
}
