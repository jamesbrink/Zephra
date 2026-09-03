import SwiftUI
import ZephraEngine

/// What can be done to the images a menu was opened over.
///
/// `items` is already the right set: the whole selection when the image pressed is part of it,
/// and only that image when it is not. Working that out is the grid's job, because the grid is
/// what knows both; the menu's job is to make the selection agree with what is about to happen,
/// so nothing changes anywhere the ring is not.
///
/// The wording counts. "Delete 4 Images" and "Delete Image" are the same menu item, and a menu
/// that said "Delete Images" over one of them would be lying about what it is about to do.
struct LibraryItemMenu: View {
    /// The images the menu acts on.
    let items: [LibraryItem]
    /// The grid's selection, made to agree with `items` the moment something is chosen.
    let selection: LibrarySelection

    @Environment(LibraryIndex.self) private var index

    var body: some View {
        if let first = items.first {
            if index.query.scope == .recentlyDeleted {
                Button("Put Back\(suffix)") { act { index.restore($0) } }
                Divider()
                Button("Delete \(noun) Immediately", role: .destructive) { act { index.purge($0) } }
            } else {
                LibraryOpenButton(item: first)
                    .disabled(items.count > 1)
                QueueVariationButton(item: first)
                    .disabled(items.count > 1)
                UseAsReferenceButton(item: first)
                    .disabled(items.count > 1)
                UpscaleMenuItems(item: first, isAlone: items.count == 1)
                Divider()
                Button(favouriteTitle) { act { index.toggleFavourite($0) } }
                AlbumMenu(ids: Set(items.map(\.id)))
                Divider()
                Button("Save as…") { act { _ in ImageExport.saveAs(files: urls) } }
                Button("Copy") { act { _ in ImageExport.copyToPasteboard(files: urls) } }
                Button("Reveal in Finder") { act { _ in ImageExport.revealInFinder(files: urls) } }
                Divider()
                Button("Delete \(noun)", role: .destructive) {
                    act { index.moveToRecentlyDeleted($0) }
                }
            }
        }
    }

    /// Moves the ring onto what is about to change, then changes it. Choosing something from a
    /// menu opened over an unselected image should leave that image selected, the way the
    /// Finder does.
    private func act(_ change: (Set<LibraryItem.ID>) -> Void) {
        let ids = Set(items.map(\.id))
        selection.ids = ids
        selection.anchor = items.first?.id
        change(ids)
    }

    private var urls: [URL] { items.map(\.url) }

    private var noun: String { items.count == 1 ? "Image" : "\(items.count) Images" }

    private var suffix: String { items.count == 1 ? "" : " \(items.count) Images" }

    /// A mixed selection is made to agree, so the word is what it is about to become.
    private var favouriteTitle: String {
        items.allSatisfy(\.isFavourite) ? "Remove from Favourites" : "Add to Favourites"
    }
}
