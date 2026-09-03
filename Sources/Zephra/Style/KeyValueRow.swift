import SwiftUI

/// One fact about an image: what it is on the left, what it says on the right.
///
/// The inspector is a column of these, so the keys line up and the values are read down one
/// edge rather than hunted for.
struct KeyValueRow<Value: View>: View {
    /// What the fact is called.
    let key: String
    /// What it says.
    let value: Value

    /// A row whose value is drawn by the call site.
    init(_ key: String, @ViewBuilder value: () -> Value) {
        self.key = key
        self.value = value()
    }

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text(key)
                .foregroundStyle(.secondary)
            Spacer(minLength: 8)
            value
                .multilineTextAlignment(.trailing)
        }
    }
}

extension KeyValueRow where Value == Text {
    /// A row whose value is a piece of text, set the way `style` asks.
    init(_ key: String, _ text: String, style: KeyValueStyle = .plain) {
        let value: Text = switch style {
        case .plain: Text(text)
        case .monospaced: Text(text).monospaced()
        case .digits: Text(text).monospacedDigit()
        }
        self.init(key) { value }
    }
}

#Preview("Facts") {
    VStack(alignment: .leading, spacing: 6) {
        KeyValueRow("Model", "Z-Image Turbo · 8-bit")
        KeyValueRow("Size", "1024 × 1024", style: .digits)
        KeyValueRow("Seed", "2B7A·40E1", style: .monospaced)
        KeyValueRow("Took") {
            Text("19.4 s").monospacedDigit().foregroundStyle(.secondary)
        }
    }
    .font(.callout)
    .padding(24)
    .frame(width: 300)
}
