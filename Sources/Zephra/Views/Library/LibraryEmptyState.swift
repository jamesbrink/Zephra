import SwiftUI
import ZephraEngine

/// What the grid shows instead of images, when there are none to show.
///
/// Four different nothings, because they mean four different things. A library with nothing in
/// it wants telling how to start; a search with no matches wants the system's own no-results
/// view, which says what was searched for; an album and Recently Deleted are simply empty, and
/// saying so is the whole message.
struct LibraryEmptyState: View {
    @Environment(LibraryIndex.self) private var index

    var body: some View {
        if !index.query.trimmedText.isEmpty {
            ContentUnavailableView.search(text: index.query.trimmedText)
        } else {
            ContentUnavailableView(title, systemImage: symbol, description: Text(message))
        }
    }

    private var title: String {
        switch index.query.scope {
        case .all: index.query.modelID == nil && index.query.tag == nil
            ? "No images yet" : "Nothing matches"
        case .favourites: "No favourites yet"
        case .lastSevenDays: "Nothing this week"
        case .album: "This album is empty"
        case .recentlyDeleted: "Nothing deleted"
        case .sources: "No source images"
        }
    }

    private var symbol: String {
        index.query.scope == .all && index.query.modelID == nil && index.query.tag == nil
            ? "photo.on.rectangle.angled"
            : index.query.scope.systemImage
    }

    private var message: String {
        switch index.query.scope {
        case .all:
            index.query.modelID == nil && index.query.tag == nil
                ? "Write a prompt on the canvas and press Generate. Everything you make lands here."
                : "Take the filters off to see the rest of the library."
        case .favourites: "Press the star on an image and it will be waiting here."
        case .lastSevenDays: "Nothing has been made in the last seven days."
        case .album: "Drop images into it from the grid, or use Add to Album."
        case .recentlyDeleted: "Deleted images wait here for thirty days before they go."
        case .sources: "Import a picture to generate from, and it will show up here."
        }
    }
}

#Preview("Empty library") {
    LibraryEmptyState()
        .frame(width: 600, height: 400)
        .environment(LibraryIndex.preview(count: 0))
}
