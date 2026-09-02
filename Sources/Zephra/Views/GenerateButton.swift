import SwiftUI
import ZephraEngine

/// The primary action. It never changes its word: Generate starts an image when the engine is
/// idle and queues one behind the running image otherwise, so firing off several prompts in a
/// row is just pressing it several times.
struct GenerateButton: View {
    @Environment(GenerationStore.self) private var store

    var body: some View {
        Button(action: store.generateFromInterface) {
            Text("Generate")
                .frame(minWidth: 78)
        }
        .buttonStyle(.borderedProminent)
        .controlSize(.large)
        .keyboardShortcut(.return, modifiers: .command)
        .disabled(!store.canQueue)
        .help(store.state.isBusy ? "Queue this prompt behind the current image" : "Generate an image")
    }
}

#Preview("Ready") {
    GenerateButton()
        .padding()
        .environment(GenerationStore.preview(state: .ready))
}
