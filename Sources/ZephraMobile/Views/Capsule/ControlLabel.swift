import SwiftUI

/// A small caption beside a control, so the settings read as labelled fields rather than as
/// loose chips. The Mac stacks its caption over the control; a phone has more height than
/// width, so here the caption leads the row.
struct ControlLabel<Content: View>: View {
    private let title: String
    private let content: Content

    init(_ title: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }

    var body: some View {
        HStack(spacing: 12) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.tertiary)
                .fixedSize()
                .frame(width: 62, alignment: .leading)
            content
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}
