import SwiftUI
import ZephraCore
import ZephraEngine

/// Marks the image on the canvas as a favourite, from the strip under it.
///
/// It can only work once the image is a file the library has indexed, which is a moment or two
/// after it is generated — the write lands, the folder watch settles, the scan runs. Until then
/// the item is not there to favourite, and the menu leaves the row out rather than offering one
/// that would quietly do nothing.
struct CanvasFavouriteButton: View {
    /// The image showing on the canvas.
    let image: GeneratedImage

    @Environment(LibraryIndex.self) private var index

    var body: some View {
        if let item {
            Button(item.isFavourite ? "Remove from Favourites" : "Add to Favourites") {
                index.toggleFavourite([item.id])
            }
        }
    }

    /// The library's record of this image, by the file it was written to.
    private var item: LibraryItem? {
        guard let url = image.fileURL else { return nil }
        return index.item(for: url.standardizedFileURL.path(percentEncoded: false))
    }
}
