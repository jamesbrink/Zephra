import SwiftUI

/// One line of a table of facts: a hairline over it, the key and the value on one line, and air
/// above and below.
///
/// The inspector's facts are drawn in three places — a library image, several of them, and the
/// run in flight — and the line they are made of is written once here, so the three tables can
/// never drift apart by a point. The text is one line, trimmed in the middle, because a seed
/// or a model name that will not fit is still recognisable by both its ends.
struct FactsRow: View {
    /// What the fact is called.
    let key: String
    /// What it says.
    let value: String
    /// Which face the value is set in.
    let style: KeyValueStyle

    init(_ key: String, _ value: String, style: KeyValueStyle = .plain) {
        self.key = key
        self.value = value
        self.style = style
    }

    var body: some View {
        VStack(spacing: 0) {
            Divider()
            KeyValueRow(key, value, style: style)
                .lineLimit(1)
                .truncationMode(.middle)
                .padding(.vertical, 7)
                .accessibilityElement(children: .combine)
        }
    }
}

#Preview("Rows") {
    FactsTable {
        FactsRow("Model", "Z-Image Turbo · 8-bit")
        FactsRow("Size", "1024 × 1024", style: .digits)
        FactsRow("Seed", "2B7A·40E1", style: .monospaced)
    }
    .padding(18)
    .frame(width: 300)
}
