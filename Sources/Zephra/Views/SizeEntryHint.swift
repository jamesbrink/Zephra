import SwiftUI
import ZephraCore

/// The line under the size field: the grid the model runs on, what a typed size off that
/// grid becomes, or why the text is not a size.
///
/// Its own view so the popover keeps its three stored properties. Red only for text that is
/// not empty and not a size; an empty field is not a mistake, only nothing yet.
struct SizeEntryHint: View {
    /// What has been typed so far.
    let text: String
    /// The model whose grid the size must land on.
    let capabilities: ModelCapabilities

    var body: some View {
        Text(hint)
            .font(.caption)
            .foregroundStyle(isValid ? .secondary : Color.red)
    }

    private var isValid: Bool { text.isEmpty || SizeEntry.typed(text) != nil }

    private var hint: String {
        guard let typed = SizeEntry.typed(text) else {
            return text.isEmpty ? SizeEntry.rule(for: capabilities) : "Width and height, like 800 × 512."
        }
        let fitted = capabilities.fit(typed)
        if fitted == typed { return SizeEntry.rule(for: capabilities) }
        return "Press Return for \(fitted.label), the nearest size this model makes."
    }
}
