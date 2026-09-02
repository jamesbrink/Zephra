import CoreTransferable
import Foundation
import UniformTypeIdentifiers
import ZephraCore

/// Lets a finished image be dragged out of the window as a PNG file.
///
/// The bytes are staged in the temporary directory first, so the receiver gets a real file
/// with a readable name rather than an anonymous blob of data.
extension GeneratedImage: @retroactive Transferable {
    /// A PNG file representation, named after the prompt and the seed.
    nonisolated public static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(exportedContentType: .png) { image in
            guard let url = ImageExport.writeTemporaryCopy(of: image) else {
                throw CocoaError(.fileWriteUnknown)
            }
            return SentTransferredFile(url)
        }
        .suggestedFileName { ImageExport.suggestedFileName(for: $0) }

        DataRepresentation(exportedContentType: .png) { ImageExport.exportData(for: $0) }
            .suggestedFileName { ImageExport.suggestedFileName(for: $0) }
    }
}
