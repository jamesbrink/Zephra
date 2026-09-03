import SwiftUI
import ZephraEngine

/// The order the library is listed in. Absent on the canvas, where there is no list to order.
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
                Label("Sort", systemImage: "arrow.up.arrow.down")
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
