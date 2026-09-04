import SwiftUI
import ZephraEngine

/// The strip over the viewer: a way back to the grid, where the shown image sits among the
/// rest, and buttons for the same steps the arrow keys already answer to.
///
/// A `safeAreaInset`, the same device `LibraryFilterBar` uses over the grid, so the picture
/// beneath keeps the full height it needs to centre itself rather than being squeezed by a row
/// stacked above it.
struct LibraryViewerBar: View {
    @Environment(WorkspaceSelection.self) private var workspace
    @Environment(LibraryIndex.self) private var index

    /// Tall enough for a 22 pt chip with air around it, matching `LibraryFilterBar`.
    private static let height: CGFloat = 42

    var body: some View {
        HStack(spacing: 14) {
            Button { workspace.viewing = nil } label: {
                Label("Library", systemImage: "chevron.backward")
            }
            .buttonStyle(.plain)
            Spacer(minLength: 12)
            if let position {
                Text("\(position.index) of \(position.count)")
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
            Button { step(.previous) } label: { Image(systemName: "chevron.left") }
                .buttonStyle(.plain)
                .disabled(!canStep(.previous))
                .help("Previous")
            Button { step(.next) } label: { Image(systemName: "chevron.right") }
                .buttonStyle(.plain)
                .disabled(!canStep(.next))
                .help("Next")
        }
        .padding(.horizontal, 20)
        .frame(height: Self.height)
        .background(.bar)
        .overlay(alignment: .bottom) {
            Rectangle().fill(ZephraChrome.hairline).frame(height: 1)
        }
    }

    private var position: LibraryViewerStep.Position? {
        workspace.viewing.flatMap { LibraryViewerStep.position(of: $0, in: index.sections) }
    }

    private func canStep(_ direction: LibraryViewerStep.Direction) -> Bool {
        guard let id = workspace.viewing else { return false }
        return LibraryViewerStep.neighbour(of: id, direction: direction, in: index.sections) != nil
    }

    private func step(_ direction: LibraryViewerStep.Direction) {
        guard let id = workspace.viewing,
              let neighbour = LibraryViewerStep.neighbour(of: id, direction: direction, in: index.sections)
        else { return }
        workspace.viewing = neighbour
    }
}

#Preview("Bar") {
    let index = PreviewImages.library(count: 8)
    let workspace = WorkspaceSelection(pane: .library)
    workspace.viewing = index.items[2].id
    return LibraryViewerBar()
        .frame(width: 700)
        .environment(workspace)
        .environment(index)
}
