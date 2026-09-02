import ZephraCore

/// A finished image that could not be written to disk.
///
/// This is a notice rather than an engine state on purpose. The pixels are in memory and on
/// the canvas either way, and a queue that is still running should not be stopped by a full
/// disk, so the store carries the most recent one and the interface shows it until the next
/// image saves cleanly.
public struct SaveFailure: Hashable, Sendable {
    /// The image whose write failed, so the interface can tell a stale notice from a fresh one.
    public let imageID: GeneratedImage.ID
    /// What the file system said, verbatim.
    public let reason: String

    /// Records one failed write.
    public init(imageID: GeneratedImage.ID, reason: String) {
        self.imageID = imageID
        self.reason = reason
    }

    /// What went wrong and what is still true, phrased for the person using the app.
    public var message: String {
        "Couldn't save this image to disk. \(reason) It is still here until you quit."
    }
}
