import SwiftUI

/// What the grid says when it has nothing to draw.
///
/// Three different nothings, and a person can act on the difference: a search that found
/// nothing, a scope with nothing in it, and a phone that has not been told about the library
/// yet. The last is the only one that is about the link, so it is the only one that mentions it.
struct LibraryEmptyState: View {
    @Environment(LibraryCatalog.self) private var catalog

    var body: some View {
        ContentUnavailableView {
            Label(title, systemImage: symbol)
        } description: {
            Text(detail)
        }
    }

    private var title: String {
        if !catalog.query.trimmedText.isEmpty { return "No Matches" }
        return switch catalog.query.scope {
        case .all: catalog.entries.isEmpty ? "Nothing Here Yet" : "Nothing to Show"
        case .favourites: "No Favorites"
        case .clips: "No Clips"
        }
    }

    private var symbol: String {
        catalog.query.trimmedText.isEmpty ? MobileTab.library.symbol : "magnifyingglass"
    }

    private var detail: String {
        if !catalog.query.trimmedText.isEmpty {
            return "Nothing in this phone's copy of the library matches what you typed."
        }
        return switch catalog.query.scope {
        case .all:
            catalog.isLive
                ? "Your Mac has not made anything yet."
                : "This phone has not been told about your library yet. "
                    + "It fills in the next time your Mac is in reach."
        case .favourites: "Pictures you mark on either device show up here."
        case .clips: "Clips your Mac makes show up here."
        }
    }
}

#Preview("Empty") {
    LibraryEmptyState()
        .environment(LibraryCatalog(libraryRoot: nil, filesRoot: nil))
}
