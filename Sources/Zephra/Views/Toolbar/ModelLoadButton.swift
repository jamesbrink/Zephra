import SwiftUI
import ZephraCore
import ZephraEngine

/// The one press that puts the chosen model's weights in, or gives them back.
///
/// Beside `ModelMenu` rather than inside it: a pill whose width changed as its state word
/// changed would shift every item to its left in the trailing group, and a view holding the
/// model, the load state and the menu's rows at once would be past the three stored properties
/// a view is allowed. It is also the visible twin of the Model menu's Load and Unload items,
/// and reads the same two answers they do, so the two cannot disagree.
///
/// Nothing here spins. A load in flight is a word in the menu's label and a determinate bar on
/// the canvas; a second indeterminate one in the toolbar would be a repeating animation, which
/// the app does not run at all.
struct ModelLoadButton: View {
    @Environment(GenerationStore.self) private var store
    @Environment(WorkspaceSelection.self) private var workspace

    var body: some View {
        if workspace.pane == .canvas, let title = status.buttonTitle {
            Button(title) { press() }
                .buttonStyle(.accessoryBar)
                .fixedSize()
                .disabled(!isEnabled)
                .help(status.help(chosen: store.descriptor, loaded: store.loadedDescriptor))
                .accessibilityLabel(title)
        }
    }

    private var status: ModelLoadStatus {
        ModelLoadStatus.status(
            of: store.descriptor, state: store.state,
            loaded: store.loadedDescriptor, residency: store.loadedResidency)
    }

    private var isEnabled: Bool {
        status.pressLoads ? store.canLoad(store.descriptor) : store.canUnload
    }

    /// Try Again is the failure's own remedy, which re-reads the launch preferences the way
    /// the canvas's button does; a plain Load is not a retry and does not go through it.
    private func press() {
        switch status {
        case .failed: store.retryFromInterface()
        case .notLoaded: store.loadModel()
        case .loaded: store.unloadModel()
        case .loading, .downloading, .building: break
        }
    }
}

#Preview("Load") {
    ModelLoadButton()
        .padding()
        .environment(GenerationStore.preview(state: .idle))
        .environment(WorkspaceSelection(pane: .canvas))
}
