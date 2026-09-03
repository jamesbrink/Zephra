import SwiftUI
import ZephraEngine

/// Owns bringing the tucked prompt back by anything other than a click on the picture or the
/// lip: Escape, a View-menu command reaching in through `WorkspaceSelection`, or simply typing.
///
/// The visual slide is `PromptTuckOverlay`'s; this view exists only to hold the focus and key
/// handling apart from it, so neither view collects more than the three stored properties
/// `AGENTS.md` allows.
struct PromptTuckHost: View {
    @Environment(WorkspaceSelection.self) private var workspace
    @Environment(GenerationStore.self) private var store
    @FocusState private var canvasFocused: Bool

    var body: some View {
        PromptTuckOverlay()
            .focusable()
            .focusEffectDisabled()
            .focused($canvasFocused)
            .onChange(of: workspace.promptTucked) { _, tucked in
                // Also takes focus off the hidden `PromptEditor`, so typing lands here rather
                // than in a text view nobody can see.
                if tucked { canvasFocused = true }
            }
            .onKeyPress(.escape) {
                guard workspace.promptTucked else { return .ignored }
                workspace.promptTucked = false
                return .handled
            }
            .onKeyPress(characters: .alphanumerics.union(.whitespaces).union(.punctuationCharacters)) { press in
                guard workspace.promptTucked else { return .ignored }
                workspace.promptTucked = false
                store.settings.prompt += press.characters
                workspace.focusPrompt()
                return .handled
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
