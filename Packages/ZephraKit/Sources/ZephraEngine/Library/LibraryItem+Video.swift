import Foundation

/// What the library knows about a clip from its poster's record: the file is not opened.
extension LibraryItem {
    /// Whether this picture is a clip's first frame.
    public var isVideo: Bool { provenance.record?.isVideo ?? false }

    /// Where the clip is, for an item whose record says it has one: beside the poster under
    /// the same stem (`VideoSidecar`). Nil for a picture. Derived from the item's own path, so
    /// it follows the file wherever the library moves it.
    public var videoURL: URL? { isVideo ? VideoSidecar.url(beside: url) : nil }

    /// How long the clip plays, in seconds, or nil for a picture.
    public var videoSeconds: Double? {
        guard let record = provenance.record, let frames = record.frameCount, frames > 1 else {
            return nil
        }
        return Double(frames) / (record.frameRate ?? 24)
    }
}
