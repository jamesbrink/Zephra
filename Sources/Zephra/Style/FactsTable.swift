import SwiftUI

/// A column of `FactsRow`s closed by a hairline, in the inspector's face.
///
/// Each row brings the line above itself, so the table adds only the one under the last; the
/// font is set here rather than on every row so a table reads as one thing.
struct FactsTable<Rows: View>: View {
    /// The rows, top to bottom.
    let rows: Rows

    init(@ViewBuilder rows: () -> Rows) {
        self.rows = rows()
    }

    var body: some View {
        VStack(spacing: 0) {
            rows
            Divider()
        }
        .font(.callout)
    }
}
