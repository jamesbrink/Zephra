import SwiftUI
import ZephraEngine

/// What the canvas says when it is not simply showing a picture: the download, the load,
/// the pace of a running generation, the empty invitation, the failure and its remedy.
///
/// Every state lands in the same centred frame, so nothing jumps as the app moves through them.
struct CanvasStateView: View {
    @Environment(GenerationStore.self) private var store

    var body: some View {
        VStack(spacing: 12) {
            if isGenerating {
                EmptyView()
            } else if isEmptyAndReady {
                Text("Describe an image to begin.")
                    .font(.system(size: 22))
                    .fontDesign(.serif)
                    .foregroundStyle(.secondary)
            } else {
                messageBlock
            }
        }
        .multilineTextAlignment(.center)
        .frame(maxWidth: 420)
        .padding(.bottom, 120)
    }

    @ViewBuilder
    private var messageBlock: some View {
        if let title = store.state.title(for: store.descriptor) {
            Text(title)
                .font(.title3)
                .foregroundStyle(.primary)
        }
        if case .downloading(let event) = store.state {
            ProgressView(value: event.fraction)
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
        if case .failed = store.state {
            Button("Try again") { store.retryFromInterface() }
                .buttonStyle(.bordered)
                .controlSize(.large)
                .padding(.top, 4)
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
        .environment(GenerationStore.preview(state: .ready))
}
