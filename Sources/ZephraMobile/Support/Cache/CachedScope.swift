/// Which collection of the cached library is being looked at.
///
/// Three of the Mac's six. A phone is a thing somebody scrolls on a sofa, so what it offers is
/// everything, the ones marked, and the ones that move; albums, Recently Deleted and sources
/// are surfaces of their own on a screen with room for a sidebar, and putting six chips across
/// a phone would make none of them readable. The Mac's own words, so the two apps name the
/// same thing the same way.
nonisolated enum CachedScope: String, CaseIterable, Identifiable, Sendable {
    /// Every picture the phone has been told about.
    case all
    /// The ones marked as favorites.
    case favourites
    /// The clips.
    case clips

    var id: String { rawValue }

    /// The word on the chip. US spelling, as everywhere on screen.
    var title: String {
        switch self {
        case .all: "All"
        case .favourites: "Favorites"
        case .clips: "Clips"
        }
    }

    /// What the day headings count under this scope, singular and plural: under Favorites, six
    /// pictures is six favorites, and calling them pictures would be counting something else.
    func noun(_ count: Int) -> String {
        switch self {
        case .all: count == 1 ? "picture" : "pictures"
        case .favourites: count == 1 ? "favorite" : "favorites"
        case .clips: count == 1 ? "clip" : "clips"
        }
    }
}
