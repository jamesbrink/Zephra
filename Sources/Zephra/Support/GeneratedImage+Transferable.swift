import CoreTransferable
import Foundation
import UniformTypeIdentifiers
import ZephraCore
import ZephraEngine

/// Lets a finished image be dragged out of the window as a file: a picture as a PNG, a clip
/// as its MP4 once the save has landed.
///
/// A picture's bytes are staged in the temporary directory first, so the receiver gets a real
/// file with a readable name rather than an anonymous blob of data. A clip's file is the one
/// beside its poster; before the save lands there is only the poster, which is what goes.
extension GeneratedImage: @retroactive Transferable {
    /// The clip's MP4 for a saved clip, a PNG named after the prompt and the seed otherwise.
    nonisolated public static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(exportedContentType: .mpeg4Movie, exporting: { image in
            guard let clip = ImageExport.savedClip(of: image) else {
                throw CocoaError(.fileNoSuchFile)
            }
            return SentTransferredFile(clip)
        })
        .exportingCondition { ImageExport.savedClip(of: $0) != nil }
        .suggestedFileName { ImageExport.savedClip(of: $0)?.lastPathComponent }

        FileRepresentation(exportedContentType: .png, exporting: { image in
            guard let url = ImageExport.writeTemporaryCopy(of: image) else {
                throw CocoaError(.fileWriteUnknown)
            }
            return SentTransferredFile(url)
        })
        .exportingCondition { ImageExport.savedClip(of: $0) == nil }
        .suggestedFileName { ImageExport.suggestedFileName(for: $0) }

        DataRepresentation(exportedContentType: .png) { ImageExport.exportData(for: $0) }
            .suggestedFileName { ImageExport.suggestedFileName(for: $0) }
    }
}
