import SwiftUI
import ZephraEngine

/// The primary action. It never changes its word: Generate starts an image when the engine is
/// idle and queues one behind the running image otherwise, so firing off several prompts in a
/// row is just pressing it several times. Beside it, `BatchCountControl` decides how many seeds
/// one press is worth.
///
/// The shortcut is written on the button rather than left to the menu bar, because Return in
/// the prompt now breaks the line instead of starting the work: somebody who has just typed a
/// prompt needs to be told what to press, at the moment they are looking for it.
struct GenerateButton: View {
    @Environment(GenerationStore.self) private var store
    @AppStorage(AppSettings.batchCount) private var count = AppSettings.initialBatchCount

    var body: some View {
        Button {
            store.generateFromInterface(count: count)
        } label: {
            HStack(spacing: 6) {
                Text("Generate")
                // The shortcut earns its width; the word no longer needs a minimum to keep the
                // button from looking pinched, and a minimum here overflows the row it sits in.
                Text("\u{2318}\u{23CE}")
                    .foregroundStyle(.secondary)
            }
        }
        .buttonStyle(.borderedProminent)
        .controlSize(.large)
        // The primary action never abbreviates itself. Without this the row squeezes the label
        // before it squeezes the space beside the settings, and "Generate" becomes "Gen…".
        .fixedSize()
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
