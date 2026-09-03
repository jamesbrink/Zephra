import CoreTransferable
import Foundation
import UniformTypeIdentifiers

/// Dragging an image out of the library.
///
/// The file itself goes, not a copy of its bytes: the PNG on disk already carries its
/// generation record and its annotation, so what lands in the Finder or in another app is the
/// same image with the same provenance, and nothing has to be written to do it.
extension LibraryItem: @retroactive Transferable {
    /// The file where it already is, named as it is already named.
    nonisolated public static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(exportedContentType: .png) { item in
            SentTransferredFile(item.url)
        }
        .suggestedFileName { $0.fileName }
    }
}
