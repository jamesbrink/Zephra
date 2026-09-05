import SwiftUI
import ZephraEngine

/// The canvas half of the window: the picture edge to edge, with the floating controls over
/// the bottom of it.
///
/// It owns the prompt's persistence, because this is where a prompt is typed: the last one is
/// restored on the way in and remembered half a second after it stops changing, and again on
/// the way out. `UserDefaults.set` is an in-memory write the system coalesces, so this is
/// tidiness rather than performance; the cost is that a quit inside the half second loses one
/// keystroke's save, which `onDisappear` covers for every way out but a crash. Loading the
/// model is `RootView`'s,
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
            .task(id: store.settings.prompt) {
                try? await Task.sleep(for: .milliseconds(500))
                guard !Task.isCancelled else { return }
                remember(store.settings.prompt)
            }
            .onDisappear { remember(store.settings.prompt) }
    }

    /// An empty field is a draft in progress, not a decision to forget the last prompt.
    private func remember(_ prompt: String) {
        guard !prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        lastPrompt = prompt
    }
}

#Preview("Canvas") {
    CanvasPane()
        .frame(width: 900, height: 700)
        .environment(ImageCache())
        .environment(WorkspaceSelection(pane: .canvas))
        .environment(GenerationStore.preview(state: .ready, image: PreviewImages.sample()))
}
