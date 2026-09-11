import Foundation
import ZephraCore
import ZephraEngine
import ZephraLinkProtocol

/// This session's pictures as the phone's filmstrip reads them.
///
/// The bytes stay on the Mac. A `GeneratedImage` carries its whole PNG and, for a clip, the MP4
/// beside it; what crosses is the file name, which is what a thumbnail or a file is later asked
/// for by. A picture whose save has not landed yet has no name, and the phone draws it as a
/// picture it cannot fetch rather than not at all.
public enum HistoryEntryProjection {
    /// One finished picture as a history row.
    public static func entry(_ image: GeneratedImage) -> HistoryEntry {
        HistoryEntry(
            id: image.id,
            fileName: image.fileURL?.lastPathComponent,
            record: GenerationRecord(image),
            isVideo: image.isVideo)
    }

    /// A whole session's history, newest first, as the store already holds it.
    public static func entries(_ images: [GeneratedImage]) -> [HistoryEntry] {
        images.map(entry)
    }
}
