import SwiftUI
import ZephraEngine

/// What sits over the grid: the filter bar, when it has something to say, and the Recently
/// Deleted strip, when that is where the grid is.
///
/// Its own view rather than a closure in `LibraryPane`, whose three stored properties are
/// spoken for: the bar's coming and going is animated, and honouring Reduce Motion there
/// needs the environment's reading, which is a property. `RecentlyDeletedNotice` is outside
/// the animated group because its own query check already gates it.
struct LibraryPaneHeader: View {
    /// What is selected in the grid, which is what shows the bar and what the strip acts on.
    let selection: LibrarySelection

    @Environment(WorkspaceSelection.self) private var workspace
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(spacing: 0) {
            Group {
                if workspace.query.isNarrowed || !selection.ids.isEmpty {
                    LibraryFilterBar(selection: selection)
                }
            }
            .animation(reduceMotion ? nil : .snappy, value: workspace.query.isNarrowed)
            .animation(reduceMotion ? nil : .snappy, value: selection.ids.isEmpty)
            RecentlyDeletedNotice(selection: selection)
        }
    }
}

#Preview("Header") {
    LibraryPaneHeader(selection: LibrarySelection())
        .frame(width: 820)
        .environment(WorkspaceSelection(pane: .library, query: LibraryQuery(scope: .favourites)))
        .environment(PreviewImages.library(count: 8))
}
