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
        if workspace.pane == .canvas {
            Button(status.buttonTitle) { press() }
                .buttonStyle(.accessoryBar)
                .fixedSize()
                .disabled(!isEnabled)
                .help(status.help(chosen: store.descriptor, loaded: store.loadedDescriptor))
                .accessibilityLabel(status.buttonTitle)
        }
    }

    private var status: ModelLoadStatus {
        ModelLoadStatus.status(
            of: store.descriptor, state: store.state,
            loaded: store.loadedDescriptor, residency: store.loadedResidency)
    }

    private var isEnabled: Bool {
        guard status.isPressable else { return false }
        return status.pressLoads ? store.canLoad(store.descriptor) : store.canUnload
    }

    /// Try Again is the failure's own remedy and goes through `retry`, which reloads over
    /// whatever is there; a plain Load is not a retry and does not go through it.
    private func press() {
        switch status {
        case .failed: store.retryFromInterface()
        case .notLoaded: store.loadModel()
        case .loaded: store.unloadModel()
        // Nothing here over a lost GPU: the press is the canvas's Relaunch Zephra, beside the
        // sentence that says why, and this pill is greyed by `isPressable`.
        case .loading, .downloading, .building, .lost: break
        }
    }
}

#Preview("Load") {
    ModelLoadButton()
        .padding()
        .environment(GenerationStore.preview(state: .idle))
        .environment(WorkspaceSelection(pane: .canvas))
}
