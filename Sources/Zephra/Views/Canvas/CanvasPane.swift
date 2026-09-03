import SwiftUI
import ZephraEngine

/// The canvas half of the window: the picture edge to edge, with the floating controls over
/// the bottom of it.
///
/// It owns the prompt's persistence, because this is where a prompt is typed: the last one is
/// restored on the way in and remembered as it changes. Loading the model is `RootView`'s,
/// which exists whichever pane is showing. `PromptTuckHost` is what lets a click on the picture
/// tuck those controls away to a lip at the bottom edge; `.clipped()` keeps the overlay's slide
/// from painting past the pane while it moves.
struct CanvasPane: View {
    @Environment(GenerationStore.self) private var store
    @AppStorage(AppSettings.lastPrompt) private var lastPrompt = ""

    var body: some View {
        CanvasView()
            .overlay(alignment: .bottom) { PromptTuckHost() }
            .clipped()
            .task {
                let saved = lastPrompt.trimmingCharacters(in: .whitespacesAndNewlines)
                if store.settings.prompt.isEmpty, !saved.isEmpty {
                    store.settings.prompt = lastPrompt
                }
            }
            .onChange(of: store.settings.prompt) { _, prompt in
                // An empty field is a draft in progress, not a decision to forget the last prompt.
                guard !prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
                lastPrompt = prompt
            }
    }
}

#Preview("Canvas") {
    CanvasPane()
        .frame(width: 900, height: 700)
        .environment(ImageCache())
        .environment(WorkspaceSelection(pane: .canvas))
        .environment(GenerationStore.preview(state: .ready, image: PreviewImages.sample()))
}
