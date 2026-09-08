import SwiftUI
import ZephraCore
import ZephraEngine

/// What the canvas says when it is not simply showing a picture: the download, the load,
/// the pace of a running generation, the empty invitation, the failure and its remedy.
///
/// Every state lands in the same centred frame, so nothing jumps as the app moves through them.
/// Over an empty canvas the words sit on the graphite; over a picture they get a floating
/// panel, because a download's progress or a failure's remedy drawn straight onto a photograph
/// cannot be read.
///
/// One state steps aside: a model that simply is not loaded, over a picture, is a note and not
/// an event. A person who opened a picture from the sidebar opened it to look at it, and a
/// panel across its middle saying the model is not up reads as the picture failing to open;
/// the panel sits at the top edge instead, remedy and all, and the picture is what the canvas
/// shows. A download, a build or a failure stays centred, since those are what is happening.
struct CanvasStateView: View {
    @Environment(GenerationStore.self) private var store
    @Environment(WorkspaceSelection.self) private var workspace

    var body: some View {
        VStack(spacing: 12) {
            // Ready has no status message. Padding and material around its empty message
            // block would otherwise leave a blank tile over the finished picture.
            if isGenerating || (store.state == .ready && store.current != nil) {
                EmptyView()
            } else if isEmptyAndReady {
                CanvasEmptyState()
            } else if store.current != nil {
                // One stack, so the panel is drawn once around the block rather than once
                // around each of the builder's views.
                VStack(spacing: 12) { messageBlock }
                    .padding(.horizontal, 28)
                    .padding(.vertical, 22)
                    .chromePanel(.floating)
            } else {
                messageBlock
            }
        }
        .multilineTextAlignment(.center)
        .frame(maxWidth: 460)
        // Room for the floating capsule, or just the lip once the prompt has tucked away.
        .padding(.bottom, stepsAside ? 0 : workspace.promptTucked ? 24 : 128)
        .padding(.top, stepsAside ? 20 : 0)
        .frame(maxHeight: .infinity, alignment: stepsAside ? .top : .center)
    }

    /// Whether the message sits at the top edge rather than over the picture: not loaded, with
    /// a picture to look at.
    private var stepsAside: Bool { store.state == .idle && store.current != nil }

    /// The model the headline is about: the one being prepared, since a picture picked up
    /// from the sidebar meanwhile moves `descriptor` without moving the load.
    private var model: ModelDescriptor { store.modelInUse ?? store.descriptor }

    @ViewBuilder
    private var messageBlock: some View {
        if let title = store.state.title(for: model, availability: store.availability[model.id]) {
            Text(title)
                .font(.title3)
                .foregroundStyle(.primary)
        }
        if let fraction = store.state.progressFraction {
            ProgressView(value: fraction)
                .progressViewStyle(.linear)
                .tint(.safelight)
                .frame(width: 260)
        }
        if let detail = store.state.detail(clip: store.runMakesClip) {
            Text(detail)
                .font(.callout)
                .monospaced()
                .monospacedDigit()
                .foregroundStyle(.secondary)
        }
        if let label = startLabel {
            Button(label) { store.retryFromInterface() }
                .buttonStyle(.bordered)
                .controlSize(.large)
                .padding(.top, 4)
        }
        if store.downloads.items.contains(where: { $0.status == .downloading || $0.status == .queued }) {
            SettingsLink { Text("View downloads in Settings") }
                .buttonStyle(.link)
        }
        if store.isStoppingPreparation {
            Text("Stopping model preparation…").foregroundStyle(.secondary)
        } else if store.state.isBusy {
            Button(isDownloading ? "Cancel Download" : "Stop") { store.cancel() }
                .buttonStyle(.link)
                .padding(.top, 2)
                .help(isDownloading ? "Cancel the download and remove its partial files" : "Stop loading the model")
        }
    }

    /// The word on the button that starts a load: the remedy after a failure, the resume after
    /// a download the user stopped. Absent whenever there is nothing to start.
    private var startLabel: String? {
        switch store.state {
        case .failed: "Try Again"
        case .idle: store.isSwappingModel ? nil : "Load Model"
        default: nil
        }
    }

    private var isGenerating: Bool {
        switch store.state {
        case .generating: true
        case .cancelling: !store.isStoppingPreparation
        default: false
        }
    }

    private var isDownloading: Bool {
        if case .downloading = store.state { return true }
        return false
    }

    private var isEmptyAndReady: Bool {
        store.state == .ready && store.current == nil
    }
}

#Preview("Empty") {
    CanvasStateView()
        .frame(width: 700, height: 460)
        .background(Color.canvasBackground)
        .environment(WorkspaceSelection(pane: .canvas))
        .environment(GenerationStore.preview(state: .ready))
}
