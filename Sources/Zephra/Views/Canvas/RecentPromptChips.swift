import SwiftUI
import ZephraEngine

/// The last few prompts, as chips on the empty canvas. A press puts one in the field and the
/// caret after it, so trying yesterday's idea again is one click and a Command-Return.
///
/// Read off the library index rather than kept anywhere; `RecentPrompts` says why. Nothing is
/// drawn when there are none, so a first launch shows the invitation alone.
struct RecentPromptChips: View {
    @Environment(GenerationStore.self) private var store
    @Environment(LibraryIndex.self) private var index
    @Environment(WorkspaceSelection.self) private var workspace

    var body: some View {
        let prompts = RecentPrompts.from(index.items, excluding: store.settings.prompt)
        if !prompts.isEmpty {
            VStack(spacing: 6) {
                Text("Recent")
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundStyle(.tertiary)
                // One under another rather than wrapped: a prompt is a sentence, and three
                // sentences read down the middle of the canvas where they would not read
                // across it.
                ForEach(prompts, id: \.self) { prompt in
                    Button {
                        store.settings.prompt = prompt
                        workspace.focusPrompt()
                    } label: {
                        Chip(prompt)
                    }
                    .buttonStyle(.plain)
                    .help(prompt)
                }
            }
            .frame(maxWidth: 460)
        }
    }
}

#Preview("Recent prompts") {
    RecentPromptChips()
        .padding(30)
        .frame(width: 520)
        .background(Color.canvasBackground)
        .environment(WorkspaceSelection(pane: .canvas))
        .environment(PreviewImages.library(count: 12))
        .environment(GenerationStore.preview(state: .ready))
}
