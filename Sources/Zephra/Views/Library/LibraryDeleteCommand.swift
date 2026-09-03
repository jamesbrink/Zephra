import SwiftUI
import ZephraEngine

/// Delete takes the selected images out of the library, and out of Recently Deleted for good.
///
/// Only the second one asks. Deleting from the library moves the files into a folder they will
/// sit in for thirty days, which is undone by walking into it and pressing Put Back; deleting
/// from that folder is the end of the picture, and the end of a picture is worth a sentence.
struct LibraryDeleteCommand: ViewModifier {
    /// What is selected in the grid.
    let selection: LibrarySelection

    @Environment(LibraryIndex.self) private var index

    func body(content: Content) -> some View {
        content
            .onKeyPress(.delete) { delete() }
            .onKeyPress(.deleteForward) { delete() }
    }

    private func delete() -> KeyPress.Result {
        guard !selection.ids.isEmpty else { return .ignored }
        index.delete(selection.ids)
        return .handled
    }
}
