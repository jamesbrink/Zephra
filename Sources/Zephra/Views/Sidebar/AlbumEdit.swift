import Foundation
import ZephraEngine

/// A change to one album that has not finished happening: the name being typed into its row, or
/// the deletion waiting on an alert.
///
/// One value for both, held by `SidebarView` rather than by the rows, because two rows renaming
/// themselves at once — or one renaming while another asks to be deleted — is a state the
/// sidebar should not be able to reach.
///
/// Making an album is deliberately not one of the kinds. The album is made the moment it is
/// asked for and what is left is a rename of it, the way the Finder makes a folder called
/// "untitled folder" and then lets you type over it. So there is one naming path rather than
/// two, and Escape leaves a real album behind instead of undoing something.
struct AlbumEdit: Identifiable, Hashable {
    /// Which change is under way.
    enum Kind: Hashable {
        /// Give an album a different name, in its own row.
        case rename
        /// Take an album away. The one album change still worth an alert: it is the only one
        /// that cannot be shrugged off by typing the old word back.
        case delete
    }

    /// Identity for the alert's presentation, so a second edit replaces the first cleanly.
    let id = UUID()
    /// Which change.
    let kind: Kind
    /// The album it is about. Not optional: both kinds are about an album that already exists.
    let album: Album
    /// What the name field currently says. Unused by `delete`.
    var name: String

    /// An edit about one album, starting from the name it has now.
    init(kind: Kind, album: Album) {
        self.kind = kind
        self.album = album
        self.name = album.name
    }

    /// Whether this edit is `album`'s own row being renamed, which is what makes that row draw
    /// a text field instead of a label.
    func isRenaming(_ album: Album) -> Bool {
        kind == .rename && self.album.id == album.id
    }

    /// The deletion alert's title. Only the deletion has an alert, so there is only one title.
    var deleteTitle: String { "Delete “\(album.name)”?" }

    /// The line under it, which is the half that says what is not being lost.
    var deleteMessage: String { "The images stay in the library. Only the album goes." }
}
