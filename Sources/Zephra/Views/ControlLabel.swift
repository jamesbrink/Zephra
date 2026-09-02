import SwiftUI

/// A small caption over a control, so the row reads as labelled fields rather than loose chips.
struct ControlLabel<Content: View>: View {
    private let title: String
    private let content: Content

    init(_ title: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.tertiary)
            content
                .frame(height: 26)
        }
    }
}

#Preview("Label") {
    ControlLabel("Steps") {
        Text("9").font(.callout)
    }
    .padding()
}
