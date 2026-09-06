import Foundation
import ZephraEngine

/// Which file leaves Zephra when an item is exported, copied, shared or dragged.
extension LibraryItem {
    /// The clip for a clip, the picture otherwise. The poster is the library's own bookkeeping;
    /// what a person means by "export the video" is the video.
    nonisolated var exportURL: URL { videoURL ?? url }
}

extension Collection where Element == LibraryItem {
    /// The files to hand out for these items.
    nonisolated var exportURLs: [URL] { map(\.exportURL) }
}
