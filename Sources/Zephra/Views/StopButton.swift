import SwiftUI
import ZephraEngine

/// The way out of a running generation. Safelight amber, and only on screen while there is
/// something to stop.
struct StopButton: View {
    @Environment(GenerationStore.self) private var store

    var body: some View {
        if isRunning {
            Button {
                store.cancel()
            } label: {
                Image(systemName: "stop.fill")
                    .frame(minWidth: 18)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .tint(.safelight)
            .foregroundStyle(Color.black.opacity(0.78))
            .disabled(store.state == .cancelling)
            .keyboardShortcut(".", modifiers: .command)
            .help(store.state == .cancelling ? "Stopping after this step" : "Stop after this step and clear the queue")
            .accessibilityLabel("Stop generating")
        }
    }

    private var isRunning: Bool {
        switch store.state {
        case .generating, .cancelling: true
        default: false
        }
    }
}

#Preview("Running") {
    StopButton()
        .padding()
        .environment(GenerationStore.preview(state: .generating(.init(phase: .denoising(step: 2, of: 9), fraction: 0.2))))
}
