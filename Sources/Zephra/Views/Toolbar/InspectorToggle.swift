import SwiftUI

/// Shows or hides the facts beside the library grid. Absent on the canvas, which has no
/// inspector to show.
struct InspectorToggle: View {
    @Environment(WorkspaceSelection.self) private var workspace

    var body: some View {
        if workspace.pane == .library {
            Button {
                workspace.inspectorVisible.toggle()
            } label: {
                Label("Inspector", systemImage: "sidebar.trailing")
                    .symbolVariant(workspace.inspectorVisible ? .fill : .none)
            }
            .keyboardShortcut("i", modifiers: [.option, .command])
            .help("Show the inspector")
        }
    }
}

#Preview("Inspector") {
    InspectorToggle()
        .padding()
        .environment(WorkspaceSelection(pane: .library))
}
