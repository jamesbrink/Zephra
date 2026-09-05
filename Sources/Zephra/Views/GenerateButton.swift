import SwiftUI
import ZephraEngine

/// The primary action. It never changes its word: Generate starts an image when the engine is
/// idle and queues one behind the running image otherwise, so firing off several prompts in a
/// row is just pressing it several times. Beside it, `BatchCountControl` decides how many seeds
/// one press is worth.
///
/// The chord is written on the button as text, because Return in the prompt breaks the line
/// instead of starting the work: somebody who has just typed a prompt needs to be told what to
/// press, at the moment they are looking for it. It is only text: the shortcut itself belongs
/// to `ZephraCommands`, which is the one owner of every chord in the app.
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
        // ⌘⏎ belongs to ZephraCommands. A shortcut declared in two places is one stray
        // SwiftUI change away from queueing twice.
        .disabled(!store.canQueue)
        .help(helpText)
    }

    private var helpText: String {
        if count > 1 {
            return "Queue \(count) seeds of this prompt"
        }
        // canQueue rather than isBusy: while a picture is being made larger nothing may be
        // queued at all, so a disabled button must not offer to queue anything behind it.
        guard store.canQueue, store.state.isBusy else { return "Generate an image" }
        return "Queue this prompt behind the current image"
    }
}

#Preview("Ready") {
    GenerateButton()
        .padding()
        .environment(GenerationStore.preview(state: .ready))
}
