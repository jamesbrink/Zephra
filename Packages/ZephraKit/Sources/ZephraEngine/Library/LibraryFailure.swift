import Foundation

/// Something the library was asked to do to a file and could not.
///
/// A notice rather than a state, for the same reason `SaveFailure` is one: the grid has already
/// shown the change optimistically and has already put it back, so what is left is telling the
/// person what the file system said. The index carries the most recent one until the next
/// operation succeeds.
public struct LibraryFailure: Hashable, Sendable {
    /// What was being attempted.
    public enum Action: Hashable, Sendable {
        /// Writing a favourite, a tag, or an album membership into an image.
        case annotate
        /// Writing the album manifest.
        case album
        /// Moving an image into Recently Deleted.
        case delete
        /// Moving one back out.
        case restore
        /// Deleting one for good.
        case purge
        /// Reading an image back to show it on the canvas.
        case open
    }

    /// Which image it was, when it was about one. Album writes are about the library.
    public let itemID: LibraryItem.ID?
    /// What was being attempted.
    public let action: Action
    /// What the file system said, verbatim.
    public let reason: String

    /// Records one failure.
    public init(itemID: LibraryItem.ID?, action: Action, reason: String) {
        self.itemID = itemID
        self.action = action
        self.reason = reason
    }

    /// What went wrong and what is still true, phrased for the person using the app.
    public var message: String {
        switch action {
        case .annotate: "Couldn't save that change to the image. \(reason)"
        case .album: "Couldn't save the album list. \(reason)"
        case .delete: "Couldn't move that image to Recently Deleted. \(reason)"
        case .restore: "Couldn't put that image back. \(reason)"
        case .purge: "Couldn't delete that image. \(reason)"
        case .open: "Couldn't open that image. \(reason) It may have been moved."
        }
    }
}
