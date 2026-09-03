import SwiftUI
import ZephraEngine

/// The order the library is listed in. Absent on the canvas, where there is no list to order.
/// The chip says the current order, the way the model chip beside it says the current model,
/// so the two read as one family rather than a word beside a glyph.
struct LibrarySortMenu: View {
    @Environment(WorkspaceSelection.self) private var workspace

    var body: some View {
        if workspace.pane == .library {
            Menu {
                ForEach(LibrarySort.allCases, id: \.self) { sort in
                    Button {
                        workspace.query.sort = sort
                    } label: {
                        if sort == workspace.query.sort {
                            Label(sort.title, systemImage: "checkmark")
                        } else {
                            Text(sort.title)
                        }
                    }
                }
            } label: {
                Text(workspace.query.sort.title)
                    .font(.callout)
            }
            .menuStyle(.button)
            .buttonStyle(.accessoryBar)
            .fixedSize()
            .help("Order the library is listed in")
            .accessibilityLabel("Sort")
        }
    }
}

#Preview("Sort") {
    LibrarySortMenu()
        .padding()
        .environment(WorkspaceSelection(pane: .library))
}
