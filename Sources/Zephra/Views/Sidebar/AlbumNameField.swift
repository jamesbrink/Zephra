import SwiftUI
import ZephraEngine

/// The text field an album's row turns into while it is being named.
///
/// Focus is entered here rather than left to the pointer, because in a `List(selection:)` the
/// first click lands on the row and selects it rather than reaching the field inside it. A field
/// nobody can type into would be worse than the alert it replaces, so `.task` puts the keyboard
/// in it as soon as the row exists. The one `Task.yield()` matters: on the first pass through
/// the list's body the row is not in a window yet, and focus set then is dropped on the floor.
/// `NSTextField` selects everything on programmatic focus, which is what gives a fresh album its
/// "Untitled Album" already highlighted and ready to be typed over.
///
/// Return commits, Escape cancels, and losing focus commits — the Finder's three answers, in the
/// Finder's order. Cancelling a fresh album leaves it called "Untitled Album" rather than
/// removing it, again as the Finder does: the album was made when it was asked for, and Escape
/// is about the name, not about the album.
struct AlbumNameField: View {
    /// The edit being typed into, shared with the sidebar that owns it. Set to nil to end it.
    @Binding var edit: AlbumEdit?

    @FocusState private var isFocused: Bool
    @Environment(LibraryIndex.self) private var index

    var body: some View {
        TextField("Name", text: name)
            .textFieldStyle(.plain)
            .lineLimit(1)
            .focused($isFocused)
            .task {
                await Task.yield()
                isFocused = true
            }
            .onSubmit { commit() }
            .onExitCommand { edit = nil }
            // Clicking away is a commit, not a cancel. Ordering is what makes that safe: Escape
            // has already set `edit` to nil by the time focus goes, and `commit` does nothing
            // without one, so an escaped rename cannot be committed on the way out.
            .onChange(of: isFocused) { _, focused in
                if !focused { commit() }
            }
    }

    /// Writes the new name, unless it is blank or is the name the album already had. Either way
    /// the edit ends, so the row goes back to being a row.
    private func commit() {
        guard let edit else { return }
        let trimmed = edit.name.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty, trimmed != edit.album.name {
            index.renameAlbum(edit.album, to: trimmed)
        }
        self.edit = nil
    }

    private var name: Binding<String> {
        Binding(get: { edit?.name ?? "" }, set: { edit?.name = $0 })
    }
}

#Preview("Naming an album") {
    @Previewable @State var edit: AlbumEdit? = AlbumEdit(
        kind: .rename, album: Album(name: "Untitled Album"))
    List {
        AlbumNameField(edit: $edit)
    }
    .listStyle(.sidebar)
    .frame(width: 280, height: 80)
    .environment(PreviewImages.library(count: 38))
}
