import SwiftUI
import ZephraEngine

/// What the canvas says when it is not simply showing a picture: the download, the load,
/// the pace of a running generation, the empty invitation, the failure and its remedy.
///
/// Every state lands in the same centred frame, so nothing jumps as the app moves through them.
/// Over an empty canvas the words sit on the graphite; over a picture they get a floating
/// panel, because a download's progress or a failure's remedy drawn straight onto a photograph
/// cannot be read.
struct CanvasStateView: View {
    @Environment(GenerationStore.self) private var store
    @Environment(WorkspaceSelection.self) private var workspace

    var body: some View {
        VStack(spacing: 12) {
            if isGenerating || store.isSwappingModel {
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
        .padding(.bottom, workspace.promptTucked ? 24 : 128)
    }

    @ViewBuilder
    private var messageBlock: some View {
        if let title = store.state.title(for: store.descriptor) {
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
        if let detail = store.state.detail {
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
        if store.state.isBusy {
            Button("Stop") { store.cancel() }
                .buttonStyle(.link)
                .padding(.top, 2)
                .help("Stop loading the model")
        }
    }

    /// The word on the button that starts a load: the remedy after a failure, the resume after
    /// a download the user stopped. Absent whenever there is nothing to start.
    private var startLabel: String? {
        switch store.state {
        case .failed: "Try again"
        case .idle: store.isSwappingModel ? nil : "Load model"
        default: nil
        }
    }

    private var isGenerating: Bool {
        switch store.state {
        case .generating, .cancelling: true
        default: false
        }
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
