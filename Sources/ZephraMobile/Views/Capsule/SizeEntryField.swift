import SwiftUI
import ZephraCore
import ZephraLinkProtocol

/// The field a size is typed into, and the one button that takes it.
///
/// Split from the sheet so the text and the focus live beside each other without the sheet
/// holding four things: the sheet is the frame and the rule, this is the entry.
struct SizeEntryField: View {
    /// What the model in force will accept, which is the grid a typed size is fitted to.
    let capabilities: CapabilitiesSummary
    /// What to do with a size that parsed.
    let take: (ImageSize) -> Void
    @State private var text = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            TextField("1024 × 1024", text: $text)
                .font(.body.monospacedDigit())
                .keyboardType(.numbersAndPunctuation)
                .autocorrectionDisabled()
                .onSubmit(use)
                .accessibilityLabel("Custom size")
            if let fitted {
                Text("Fits to \(fitted.label)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Button("Use This Size", action: use)
                .buttonStyle(.borderedProminent)
                .disabled(fitted == nil)
        }
    }

    /// What the typed text would actually run at, or nil while it names no size.
    private var fitted: ImageSize? {
        SizeEntry.parse(text, for: capabilities.capabilities)
    }

    private func use() {
        guard let fitted else { return }
        take(fitted)
    }
}
