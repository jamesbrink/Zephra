import Foundation
import ZephraEngine

/// A change to the album list that is waiting on the person to confirm it.
///
/// One value for all three — make, rename, delete — because they are one alert with different
/// words in it, and because holding them as three separate flags is how a sidebar ends up
/// showing two alerts at once.
struct AlbumEdit: Identifiable, Hashable {
    /// Which change is being asked about.
    enum Kind: Hashable {
        /// Make a new album.
        case create
        /// Give an existing one a different name.
        case rename
        /// Take an existing one away.
        case delete
    }

    /// Identity for the alert's presentation, so a second edit replaces the first cleanly.
    let id = UUID()
    /// Which change.
    let kind: Kind
    /// The album it is about, or nil when making one.
    let album: Album?
    /// What the name field currently says. Unused by `delete`.
    var name: String

    /// An edit about an album, or about no album yet.
    init(kind: Kind, album: Album? = nil) {
        self.kind = kind
        self.album = album
        self.name = album?.name ?? ""
    }

    /// The alert's title.
    var title: String {
        switch kind {
        case .create: "New Album"
        case .rename: "Rename Album"
        case .delete: "Delete “\(album?.name ?? "")”?"
        }
    }

    /// What the button that goes through with it says.
    var confirmTitle: String {
        switch kind {
        case .create: "Create"
        case .rename: "Rename"
        case .delete: "Delete"
        }
    }

    /// The line under the title, where there is one worth saying.
    var message: String? {
        switch kind {
        case .create, .rename: nil
        case .delete: "The images stay in the library. Only the album goes."
        }
    }

    /// Whether the alert shows a name field.
    var isNaming: Bool { kind != .delete }

    /// Whether the confirm button can be pressed: a name that is only spaces is not a name.
    var isReady: Bool {
        !isNaming || !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}
