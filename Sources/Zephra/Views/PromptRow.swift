import SwiftUI
import ZephraEngine

/// The prompt, what to avoid under it, and the picture to edit beside them.
///
/// One row rather than a field with another row beneath it. The well is 44 points tall and the
/// prompt at rest was one line, so stacking them left a band the width of the capsule that
/// belonged to nothing: it looked like part of the text area and behaved like the background.
/// Now the field is as tall as the whole band, and everything in the band that is not the well
/// or the negative prompt is the field — including the corner under the well, which is why the
/// click target is a layer behind the row rather than the field's own frame.
struct PromptRow: View {
    @Environment(GenerationStore.self) private var store
    @Environment(WorkspaceSelection.self) private var workspace
    @State private var promptFocused = false

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 6) {
                PromptEditor(focus: $promptFocused)
                NegativePromptField()
            }
            .frame(maxWidth: .infinity, alignment: .topLeading)
            ReferenceImageWell()
        }
        // Behind the row, so the text still takes its own clicks and puts the caret where it was
        // clicked, the well still takes its own, and only the space neither of them wants ends
        // up here — where it means "start typing" rather than nothing at all.
        .background {
            Rectangle()
                .fill(.clear)
                .contentShape(Rectangle())
                .onTapGesture { promptFocused = true }
        }
        // `PromptTuckHost` bumps this as the prompt tucks away, so the caret is in the hidden
        // editor and what is typed while the capsule is down lands here rather than nowhere.
        .onChange(of: workspace.promptFocusToken) { promptFocused = true }
        // The menu bar's one question about this field: ⌘⌫ means the line under the caret while
        // it is here, so the Delete item has to stand down (`CommandTarget.whileTyping(_:)`).
        // Published from the row rather than from the editor because the row is where the focus
        // lives, and nil rather than false so it goes away with the canvas.
        .focusedSceneValue(\.promptHasKeyboard, promptFocused ? true : nil)
    }
}

#Preview("Prompt row") {
    PromptRow()
        .padding()
        .frame(width: 520)
        .environment(ImageCache())
        .environment(WorkspaceSelection(pane: .canvas))
        .environment(GenerationStore.preview(state: .ready))
}

#Preview("Prompt row for an editing model") {
    PromptRow()
        .padding()
        .frame(width: 520)
        .environment(ImageCache())
        .environment(WorkspaceSelection(pane: .canvas))
        .environment(GenerationStore.preview(state: .ready, descriptor: PreviewModel.editing))
}

#Preview("Prompt row with a negative prompt") {
    PromptRow()
        .padding()
        .frame(width: 520)
        .environment(ImageCache())
        .environment(WorkspaceSelection(pane: .canvas))
        .environment(GenerationStore.preview(state: .ready, descriptor: PreviewModel.guided))
}
