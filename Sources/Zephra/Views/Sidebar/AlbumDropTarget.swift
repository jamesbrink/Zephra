import SwiftUI
import ZephraEngine

/// Makes a sidebar row take images dropped on it.
///
/// A modifier rather than more lines in `AlbumSourceRow`, because being a drop target is a whole
/// small behaviour with state of its own, and because the row would otherwise hold four things:
/// its album, the sidebar's edit, the library, and the grid's selection. The row keeps the first
/// three and hands this one a closure, so what is filed is the row's business and what counts as
/// a drop is this file's.
///
/// A cell is dragged one at a time, so a drag that started inside the selection stands for the
/// whole of it — the same rule the grid's own context menu follows, and the one a person expects
/// after choosing four pictures and pulling on one of them. The selection comes from the scene
/// rather than from the row, because the grid publishes it and the sidebar is not inside it.
struct AlbumDropTarget: ViewModifier {
    /// What to do with the images that landed.
    let onFile: (Set<LibraryItem.ID>) -> Void

    @State private var isTargeted = false
    @FocusedValue(\.librarySelection) private var selection

    func body(content: Content) -> some View {
        content
            .frame(maxWidth: .infinity)
            .contentShape(Rectangle())
            .dropDestination(for: LibraryItemReference.self) { references, _ in
                let dropped = Set(references.map(\.id))
                guard !dropped.isEmpty else { return false }
                onFile(expanded(dropped))
                return true
            } isTargeted: { isTargeted = $0 }
            .listRowBackground(isTargeted ? Optional(highlight) : nil)
    }

    /// The whole selection when the dropped image is part of it, and just that image otherwise.
    private func expanded(_ dropped: Set<LibraryItem.ID>) -> Set<LibraryItem.ID> {
        guard let selection, dropped.contains(where: selection.contains) else { return dropped }
        return dropped.union(selection.ids)
    }

    /// The accent ring while a drag is over the row. It is set as the row's background only
    /// then, and nothing at all otherwise — nothing rather than a clear rectangle, because any
    /// row background at all replaces the list's own selection highlight, so a row that always
    /// set one would stop looking selected.
    private var highlight: some View {
        RoundedRectangle(cornerRadius: ZephraChrome.fieldRadius, style: .continuous)
            .strokeBorder(Color.accentColor, lineWidth: 2)
    }
}
