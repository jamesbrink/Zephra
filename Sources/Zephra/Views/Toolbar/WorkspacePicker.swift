import SwiftUI

/// Canvas or Library, as a segmented control. The window's one navigational choice, so it sits
/// where the eye goes for one: the right-hand end of the title bar, next to the model.
struct WorkspacePicker: View {
    @Environment(WorkspaceSelection.self) private var workspace

    var body: some View {
        @Bindable var workspace = workspace
        Picker("Pane", selection: $workspace.pane) {
            ForEach(WorkspacePane.allCases) { pane in
                Label(pane.title, systemImage: pane.systemImage)
                    .tag(pane)
            }
        }
        .pickerStyle(.segmented)
        .labelsHidden()
        .help("Show the canvas or the library")
    }
}

#Preview("Pane") {
    WorkspacePicker()
        .padding()
        .environment(WorkspaceSelection(pane: .canvas))
}
