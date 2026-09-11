import UIKit

/// Bytes turned into a picture, off the main actor.
///
/// One line, in one place, because it is the line that must never be written anywhere else: a
/// full-size PNG off a Mac is tens of milliseconds to decode, and every one of those spent on
/// the main actor is a frame dropped in the middle of a scroll. The Mac's rule, in the phone's
/// toolkit — nothing there decodes an image on the main actor either.
///
/// There is no cache behind it. Whole pictures are held by `FileStore` as files, thumbnails by
/// `ThumbnailStore`, and a second copy of the same bytes decoded in memory would be a third
/// place for a picture to go stale.
enum DecodedPicture {
    /// `data` as a picture, or nil where the bytes are not one this phone can read.
    static func from(_ data: Data) async -> UIImage? {
        await Task.detached { UIImage(data: data) }.value
    }

    /// The picture in a file on this phone, read and decoded off the main actor.
    ///
    /// The file rather than bytes handed in, for the viewer: a whole picture off a Mac is
    /// megabytes, and reading it into memory on the main actor to decode it there costs the
    /// read as well as the decode.
    static func contentsOf(_ url: URL) async -> UIImage? {
        await Task.detached { UIImage(contentsOfFile: url.path(percentEncoded: false)) }.value
    }
}
