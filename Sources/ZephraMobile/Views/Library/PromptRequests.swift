import SwiftUI

struct PromptRequests: ViewModifier {
    @State private var entry: CachedEntry?

    func body(content: Content) -> some View {
        content
            .environment(\.viewImagePrompt) { entry = $0 }
            .sheet(item: $entry) { PromptSheet(entry: $0) }
    }
}

extension EnvironmentValues {
    @Entry var viewImagePrompt: (CachedEntry) -> Void = { _ in }
}
