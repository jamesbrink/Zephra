import SwiftUI
import ZephraEngine

/// The strip over the grid: what is narrowing it, and how much of it there is.
///
/// `LibraryPane` shows this only when there is something to say — a query with tokens on it, or
/// a live selection — so an unfiltered library with nothing chosen shows the grid alone. A
/// safe-area inset rather than a row above the scroll view, so the grid scrolls under it and
/// the window's own material shows through — and so the scroll view keeps the full height it
/// needs to place a section heading correctly.
struct LibraryFilterBar: View {
    /// What is selected in the grid, for the count on the left.
    let selection: LibrarySelection

    var body: some View {
        HStack(spacing: 10) {
            LibraryFilterTokens()
            LibrarySelectionCount(selection: selection)
            Spacer(minLength: 12)
        }
        .padding(.horizontal, 20)
        .frame(height: ZephraChrome.barHeight)
        .background(.bar)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(ZephraChrome.hairline)
                .frame(height: 1)
        }
    }
}

#Preview("Filter bar") {
    LibraryFilterBar(selection: LibrarySelection())
        .frame(width: 820)
        .environment(WorkspaceSelection(
            pane: .library,
            query: LibraryQuery(scope: .favourites)
        ))
        .environment(PreviewImages.library(count: 38))
}
