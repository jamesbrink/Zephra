import CoreTransferable
import Foundation
import ZephraEngine

/// One library image on its way from the grid to somewhere else inside Zephra: its identity, and
/// nothing else.
///
/// A drag out of the library exports the file, which is what the Finder and every other app
/// want. Inside the app that is the wrong shape entirely — a `FileRepresentation` cannot be
/// received by a `dropDestination`, and filing an image into an album needs the item's id, not a
/// copy of its bytes on the way past. So the item exports this first and the file second, and an
/// album row asks only for this: a drop of a picture from the Finder is then not an album drop
/// at all, which is the right answer.
///
/// The id is the standardized path (`LibraryItem.ID`), so a payload that arrives after the file
/// has moved simply matches nothing.
struct LibraryItemReference: Codable, Transferable {
    /// The path of the image being dragged.
    let id: LibraryItem.ID

    nonisolated static var transferRepresentation: some TransferRepresentation {
        CodableRepresentation(contentType: .zephraLibraryItem)
    }
}
