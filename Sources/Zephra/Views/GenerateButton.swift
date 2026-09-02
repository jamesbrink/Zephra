import SwiftUI
import ZephraEngine

/// The primary action, and the way out of it. The verb never changes: Generate, then
/// Generating…, then Generate again. Amber shows up only while the model is working.
struct GenerateButton: View {
    @Environment(GenerationStore.self) private var store

    var body: some View {
        HStack(spacing: 8) {
            if isRunning {
                Button {
                    store.cancel()
                } label: {
                    Image(systemName: "stop.fill")
                }
                .buttonStyle(.bordered)
                .controlSize(.large)
                .help("Stop after this step")
                .accessibilityLabel("Stop generating")
                .disabled(store.state == .cancelling)
            }
            Button(action: store.generate) {
                Text(label)
                    .frame(minWidth: 78)
                    .foregroundStyle(isRunning ? AnyShapeStyle(Color.black.opacity(0.75)) : AnyShapeStyle(.white))
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .tint(isRunning ? Color.safelight : nil)
            .disabled(!store.canGenerate)
        }
    }

    private var label: String {
        switch store.state {
        case .generating: "Generating…"
        case .cancelling: "Stopping…"
        default: "Generate"
        }
    }

    private var isRunning: Bool {
        switch store.state {
        case .generating, .cancelling: true
        default: false
        }
    }
}

#Preview("Ready") {
    GenerateButton()
        .padding()
        .environment(GenerationStore.preview(state: .ready))
}
