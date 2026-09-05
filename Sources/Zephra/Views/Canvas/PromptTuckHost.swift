import SwiftUI
import ZephraEngine

/// Owns bringing the tucked prompt back by anything other than a click on the picture or the
/// lip: Escape, a View-menu command reaching in through `WorkspaceSelection`, or simply typing.
///
/// Tucking is visual only. `PromptTuckOverlay` slides the capsule off the bottom edge and the
/// prompt's text view stays first responder underneath it — this view hands it the caret as the
/// prompt tucks, and never takes the keyboard for itself — so whatever is typed lands in the
/// real editor, composed input included: a Japanese input source builds its text inside the
/// field the way it always did, and the first change to the prompt is what brings the capsule
/// back. An earlier version focused itself and appended each keystroke's raw characters to the
/// prompt, which put the letters in but broke every input method that composes them. Escape
/// arrives as `cancelOperation:`, which the text view forwards up the chain to `onExitCommand`.
///
/// The visual slide is `PromptTuckOverlay`'s; this view exists only to keep the coming-back
/// apart from it, so neither view collects more than the three stored properties `AGENTS.md`
/// allows.
struct PromptTuckHost: View {
    @Environment(WorkspaceSelection.self) private var workspace
    @Environment(GenerationStore.self) private var store

    var body: some View {
        PromptTuckOverlay()
            .onChange(of: workspace.promptTucked) { _, tucked in
                // The caret goes to the hidden editor as the prompt tucks, so a keystroke has
                // somewhere to land even when the click that tucked it took the focus away.
                if tucked { workspace.focusPrompt() }
            }
            .onChange(of: store.settings.prompt) { _, _ in
                guard workspace.promptTucked else { return }
                workspace.promptTucked = false
            }
            .onExitCommand {
                guard workspace.promptTucked else { return }
                workspace.promptTucked = false
            }
    }
}

#Preview("Tucked, ready to type") {
    let workspace = WorkspaceSelection(pane: .canvas)
    workspace.promptTucked = true
    return PromptTuckHost()
        .frame(width: 900, height: 500)
        .background(Color.canvasBackground)
        .environment(ImageCache())
        .environment(workspace)
        .environment(GenerationStore.preview(state: .ready, image: PreviewImages.sample()))
}
