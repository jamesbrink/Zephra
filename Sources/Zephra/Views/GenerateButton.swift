import SwiftUI
import ZephraEngine

/// The primary action. It never changes its word: Generate starts an image when the engine is
/// idle and queues one behind the running image otherwise, so firing off several prompts in a
/// row is just pressing it several times. Beside it, `BatchCountControl` decides how many seeds
/// one press is worth.
struct GenerateButton: View {
    @Environment(GenerationStore.self) private var store
    @AppStorage(AppSettings.batchCount) private var count = AppSettings.initialBatchCount

    var body: some View {
        Button {
            store.generateFromInterface(count: count)
        } label: {
            Text("Generate")
                .frame(minWidth: 78)
        }
        .buttonStyle(.borderedProminent)
        .controlSize(.large)
        .keyboardShortcut(.return, modifiers: .command)
        .disabled(!store.canQueue)
        .help(helpText)
    }

    private var helpText: String {
        if count > 1 {
            return "Queue \(count) seeds of this prompt"
        }
        return store.state.isBusy ? "Queue this prompt behind the current image" : "Generate an image"
    }
}

#Preview("Ready") {
    GenerateButton()
        .padding()
        .environment(GenerationStore.preview(state: .ready))
}
