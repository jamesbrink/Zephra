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
        // The relaunch needs nothing the store can withhold — over a lost GPU `canLoad` is
        // false for the rest of the launch, and a pill named for the one remedy that always
        // works must never be the greyed one.
        if status == .lost { return true }
        return status.pressLoads ? store.canLoad(store.descriptor) : store.canUnload
    }

    /// Try Again is the failure's own remedy and goes through `retry`, which reloads over
    /// whatever is there; a plain Load is not a retry and does not go through it.
    private func press() {
        switch status {
        case .failed: store.retryFromInterface()
        case .notLoaded: store.loadModel()
        case .loaded: store.unloadModel()
        // The word above and this press are one thing: the same `Relaunch.thisApp()` the
        // canvas's Relaunch Zephra runs, whichever of the two is pressed first behind the
        // launch's one-shot.
        case .lost: Relaunch.thisApp()
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
