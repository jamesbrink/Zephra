import SwiftUI
import ZephraEngine

/// The canvas half of the window: the picture edge to edge, with the floating controls over
/// the bottom of it.
///
/// It also owns the prompt's persistence, because this is where a prompt is typed. The last
/// one is restored on the way in and remembered as it changes.
struct CanvasPane: View {
    @Environment(GenerationStore.self) private var store
    @AppStorage(AppSettings.lastPrompt) private var lastPrompt = ""

    var body: some View {
        CanvasView()
            .overlay(alignment: .bottom) { CanvasOverlay() }
            .task {
                let saved = lastPrompt.trimmingCharacters(in: .whitespacesAndNewlines)
                if store.settings.prompt.isEmpty, !saved.isEmpty {
                    store.settings.prompt = lastPrompt
                }
                await store.bootstrapFromInterface()
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
