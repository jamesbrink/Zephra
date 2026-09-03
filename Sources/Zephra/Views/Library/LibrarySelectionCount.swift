import SwiftUI
import ZephraEngine

/// How many images the grid is showing, and how many of them are chosen.
///
/// Figures of one width, because both halves change while the eye is on them — a selection
/// sweep would otherwise make the line jitter sideways as it counted.
struct LibrarySelectionCount: View {
    /// What is selected in the grid.
    let selection: LibrarySelection

    @Environment(LibraryIndex.self) private var index

    var body: some View {
        Text(label)
            .font(.caption)
            .foregroundStyle(.secondary)
            .monospacedDigit()
            .lineLimit(1)
            .accessibilityLabel(label)
    }

    private var label: String {
        let shown = index.count(for: index.query)
        let images = "\(shown) \(shown == 1 ? "image" : "images")"
        guard selection.count > 0 else { return images }
        return "\(images) \(ImageFacts.separator) \(selection.count) selected"
    }
}

#Preview("Counts") {
    LibrarySelectionCount(selection: LibrarySelection())
        .padding(20)
        .environment(LibraryIndex.preview(count: 38))
}
