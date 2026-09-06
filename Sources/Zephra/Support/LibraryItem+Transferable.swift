import CoreTransferable
import Foundation
import UniformTypeIdentifiers

/// Dragging an image out of the library, and around inside it.
///
/// Two representations, in the order that decides who gets which. Inside Zephra the drag is
/// about the image, so an id goes first and an album row asks for exactly that. Out of Zephra
/// the file itself goes, not a copy of its bytes: the PNG on disk already carries its generation
/// record and its annotation, so what lands in the Finder or in another app is the same image
/// with the same provenance, and nothing has to be written to do it.
///
/// The order is the whole of it. A receiver takes the first representation it understands, and
/// only Zephra understands `io.zephra.library-item`, so the Finder still gets the file.
extension LibraryItem: @retroactive Transferable {
    /// The identity first, for drops inside the app; the file after it, for everywhere else.
    nonisolated public static var transferRepresentation: some TransferRepresentation {
        ProxyRepresentation(exporting: { LibraryItemReference(id: $0.id) })
        FileRepresentation(exportedContentType: .png) { item in
            SentTransferredFile(item.exportURL)
        }
        .suggestedFileName { $0.fileName }
    }
}
