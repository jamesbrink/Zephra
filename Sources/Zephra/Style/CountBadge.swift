import SwiftUI

/// How many things are behind a sidebar row, set in figures of one width so a column of them
/// does not shuffle sideways as the numbers change.
struct CountBadge: View {
    /// The number to show.
    let value: Int

    /// A badge for one count.
    init(_ value: Int) {
        self.value = value
    }

    var body: some View {
        Text(value, format: .number)
            .monospacedDigit()
            .foregroundStyle(.tertiary)
    }
}

#Preview("Counts") {
    VStack(alignment: .trailing, spacing: 4) {
        CountBadge(1284)
        CountBadge(38)
        CountBadge(0)
    }
    .font(.callout)
    .padding(24)
}
