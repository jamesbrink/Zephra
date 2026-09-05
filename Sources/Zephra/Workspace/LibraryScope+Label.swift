import Foundation
import ZephraEngine

/// What each collection of the library is called on screen, and the symbol beside it.
///
/// In the app rather than in `ZephraEngine`, because a scope is a value and what it is called
/// is a matter of copy. The engine has no opinion about the word "Favorites".
extension LibraryScope {
    /// The row's title, for the collections that name themselves.
    var title: String {
        title(albumName: { _ in nil })
    }

    /// The row's title, with albums named by whatever owns their names.
    ///
    /// An album has no name of its own — the album manifest holds it — so one is asked for by
    /// id: `SidebarView` passes `LibraryIndex.name(of:)`. For an album whose name has gone
    /// missing, the generic word stands in rather than a raw UUID.
    func title(albumName: (UUID) -> String?) -> String {
        switch self {
        case .all: "All images"
        case .favourites: "Favorites"
        case .lastSevenDays: "Last 7 days"
        case .album(let id): albumName(id) ?? "Album"
        case .recentlyDeleted: "Recently deleted"
        case .sources: "Source images"
        }
    }

    /// The symbol before it.
    var systemImage: String {
        switch self {
        case .all: "photo.on.rectangle"
        case .favourites: "star"
        case .lastSevenDays: "clock"
        case .album: "rectangle.stack"
        case .recentlyDeleted: "trash"
        case .sources: "photo.badge.plus"
        }
    }
}
