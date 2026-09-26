import SwiftUI

/// Short prompts fit their text; long or enlarged prompts scroll without truncation.
struct ViewerPromptExcerpt: View {
    let text: String
    @State private var contentHeight: CGFloat = 120

    var body: some View {
        ScrollView(.vertical) {
            Text(text)
                .font(.footnote)
                .frame(maxWidth: .infinity, alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)
                .foregroundStyle(.white)
                .onGeometryChange(for: CGFloat.self) { $0.size.height } action: {
                    contentHeight = $0
                }
        }
        .frame(height: min(contentHeight, 120))
        .scrollBounceBehavior(.basedOnSize)
    }
}
