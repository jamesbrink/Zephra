import SwiftUI

struct ViewPromptButton: View {
    let entry: CachedEntry
    @Environment(\.viewImagePrompt) private var show

    var body: some View {
        Button("View Prompt", systemImage: "text.alignleft") { show(entry) }
            .disabled(entry.prompt.isEmpty)
    }
}
