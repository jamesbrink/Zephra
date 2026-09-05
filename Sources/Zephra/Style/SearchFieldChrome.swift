import SwiftUI

/// The look of a search field: a magnifier at its leading edge, a quiet rounded fill, and the
/// height of one line of `.callout`.
///
/// One modifier for the sidebar's search and the reference picker's, which are bound to
/// different text and must never look different. Applied to the field, or to a row holding
/// the field and a hint beside it; the magnifier is added here so no caller forgets it.
struct SearchFieldChrome: ViewModifier {
    func body(content: Content) -> some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass")
                .font(.caption)
                .foregroundStyle(.tertiary)
            content
        }
        .padding(.horizontal, 8)
        .frame(height: ZephraChrome.fieldHeight)
        .background(
            .quaternary,
            in: RoundedRectangle(cornerRadius: ZephraChrome.fieldRadius, style: .continuous)
        )
    }
}

extension View {
    /// Dresses this field as one of the app's search fields.
    func searchFieldChrome() -> some View {
        modifier(SearchFieldChrome())
    }
}

#Preview("Search field") {
    @Previewable @State var text = ""
    TextField("Search", text: $text)
        .textFieldStyle(.plain)
        .font(.callout)
        .searchFieldChrome()
        .padding()
        .frame(width: 280)
}
