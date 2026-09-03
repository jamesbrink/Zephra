import Foundation
import ZephraCore
import ZephraEngine

/// What each thing narrowing the library is called on the chip that can take it off again.
///
/// In the app rather than in `ZephraEngine`, like every other piece of copy. A token names
/// something by identity — an album by its UUID, a model by its descriptor identifier — and
/// neither of those is a word, so both have to be looked up somewhere that knows the names.
extension LibraryQueryToken {
    /// The word on the chip. `albumName` is the library index's own lookup, so a renamed album
    /// reads by its new name at once.
    func title(albumName: (UUID) -> String?) -> String {
        switch self {
        case .scope(let scope): scope.title(albumName: albumName)
        case .model(let id): ModelCatalog.descriptor(id: id)?.fullName ?? id
        case .tag(let tag): tag
        case .search(let text): "“\(text)”"
        }
    }
}
