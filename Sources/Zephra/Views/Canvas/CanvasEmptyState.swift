import SwiftUI
import ZephraEngine
import ZephraStyle

/// The canvas with nothing on it: the invitation, how to answer it, and the last few things
/// that were asked for.
///
/// An empty canvas used to be one serif line over a dark pane, with the inspector beside it
/// saying it had nothing to say either. The line stays — it is the one place the serif
/// belongs — and under it the two ways in: the shortcut, and on a model that reads a picture,
/// dropping one here. The recent prompts are a third: a press puts one back in the field.
struct CanvasEmptyState: View {
    @Environment(GenerationStore.self) private var store

    var body: some View {
        VStack(spacing: 10) {
            Text("Describe an image to begin.")
                // The system's title, 22 pt at the default size, so it follows the type
                // size the person chose rather than standing at a number of its own.
                .font(.title)
                .fontDesign(.serif)
                .foregroundStyle(.secondary)
            Text(hint)
                .font(.callout)
                .foregroundStyle(.tertiary)
            RecentPromptChips()
                .padding(.top, 14)
        }
        .multilineTextAlignment(.center)
    }

    /// The shortcut, and the drop only where a drop would do something.
    private var hint: String {
        let generate = "Press \u{2318}\u{21A9} to generate"
        guard store.descriptor.capabilities.supportsReferenceImage else { return generate }
        return "\(generate) \u{00B7} or drop a picture here to start from it"
    }
}

#Preview("Empty") {
    CanvasEmptyState()
        .frame(width: 700, height: 400)
        .background(Color.canvasBackground)
        .environment(WorkspaceSelection(pane: .canvas))
        .environment(PreviewImages.library(count: 12))
        .environment(GenerationStore.preview(state: .ready, descriptor: PreviewModel.editing))
}
