import SwiftUI
import ZephraEngine
import ZephraStyle

/// The way out of a running generation. Safelight amber, and only on screen while there is
/// something to stop.
///
/// A bordered button that says "Stop" rather than a filled square: a square with no word
/// beside Generate read as a decoration, and the prominent style drew it in the window's
/// grey rather than in amber. The word and the symbol take the safelight colour directly.
struct StopButton: View {
    @Environment(GenerationStore.self) private var store

    var body: some View {
        if isRunning {
            Button {
                store.cancel()
            } label: {
                Label("Stop", systemImage: "stop.fill")
                    .labelStyle(.titleAndIcon)
                    .foregroundStyle(Color.safelight)
            }
            .buttonStyle(.bordered)
            .controlSize(.large)
            .tint(.safelight)
            .disabled(store.state == .cancelling)
            // ⌘. belongs to ZephraCommands. A shortcut declared in two places is one stray
            // SwiftUI change away from stopping twice.
            .help(store.state == .cancelling ? "Stopping after this step" : "Stop after this step and clear the queue")
            .accessibilityLabel("Stop generating")
        }
    }

    private var isRunning: Bool {
        switch store.state {
        case .generating, .upscaling, .cancelling: true
        default: false
        }
    }
}

#Preview("Running") {
    StopButton()
        .padding()
        .environment(GenerationStore.preview(state: .generating(.init(phase: .denoising(step: 2, of: 9), fraction: 0.2))))
}
