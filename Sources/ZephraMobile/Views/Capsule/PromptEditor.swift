import SwiftUI

/// What the picture should show.
///
/// Three lines to start with, growing with what is typed, because a prompt is usually a
/// sentence and sometimes a paragraph, and a field that scrolls at one line hides most of what
/// somebody wrote. `TextEditor` rather than a `TextField`: the Mac's prompt takes returns as
/// line breaks, and so does this.
///
/// The keyboard is `MobileSelection`'s wish mirrored into `@FocusState` here. The tap that
/// opens the capsule is on a view that is gone before this one exists, so it cannot focus a
/// field that has not been built; what it can do is say the prompt wants the keyboard, and
/// this editor answers it on the first pass after it is mounted. The one `Task.yield()` is
/// `AlbumNameField`'s rule on the Mac: focus set in the same pass as the view's first layout
/// is dropped.
struct PromptEditor: View {
    @Environment(PromptDraft.self) private var draft
    /// Where the phone is looking, which is where the wish for the keyboard is kept.
    @Environment(MobileSelection.self) private var selection
    /// Whether this editor holds the keyboard. SwiftUI's own truth, mirrored both ways.
    @FocusState private var isFocused: Bool

    var body: some View {
        @Bindable var draft = draft
        TextEditor(text: $draft.settings.prompt)
            .font(.callout)
            .scrollContentBackground(.hidden)
            .frame(minHeight: 66)
            .fixedSize(horizontal: false, vertical: true)
            .focused($isFocused)
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
            .contentShape(Rectangle())
            .onTapGesture { isFocused = true }
            .accessibilityLabel("Prompt")
            .task {
                await Task.yield()
                isFocused = selection.promptIsFocused
            }
            .onChange(of: selection.promptIsFocused) { isFocused = selection.promptIsFocused }
            .onChange(of: isFocused) { selection.promptIsFocused = isFocused }
            .toolbar {
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("Done") { selection.collapseCapsule() }
                }
            }
    }
}
