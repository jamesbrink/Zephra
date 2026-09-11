import SwiftUI

/// What the picture should show.
///
/// Three lines to start with, growing with what is typed, because a prompt is usually a
/// sentence and sometimes a paragraph, and a field that scrolls at one line hides most of what
/// somebody wrote. `TextEditor` rather than a `TextField`: the Mac's prompt takes returns as
/// line breaks, and so does this.
struct PromptEditor: View {
    @Environment(PromptDraft.self) private var draft

    var body: some View {
        @Bindable var draft = draft
        TextEditor(text: $draft.settings.prompt)
            .font(.callout)
            .scrollContentBackground(.hidden)
            .frame(minHeight: 66)
            .fixedSize(horizontal: false, vertical: true)
            .overlay(alignment: .topLeading) {
                if draft.settings.prompt.isEmpty {
                    Text("Describe a picture…")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .padding(.top, 8)
                        .padding(.leading, 5)
                        .allowsHitTesting(false)
                }
            }
            .accessibilityLabel("Prompt")
    }
}
