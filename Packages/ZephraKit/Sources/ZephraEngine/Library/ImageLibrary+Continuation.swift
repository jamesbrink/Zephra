import Foundation

/// Finding the clip a continuation carries on.
extension ImageLibrary {
    /// The poster and the MP4 of the clip whose poster is named `name`, in the images folder
    /// or else in Recently Deleted; nil when neither holds both files.
    public func sourceClip(named name: String) -> (poster: URL, mp4: URL)? {
        for folder in [root, directory(for: .recentlyDeleted)] {
            let poster = folder.appending(path: name)
            let mp4 = VideoSidecar.url(beside: poster)
            if FileManager.default.fileExists(atPath: poster.path(percentEncoded: false)),
                FileManager.default.fileExists(atPath: mp4.path(percentEncoded: false))
            {
                return (poster, mp4)
            }
        }
        return nil
    }
}
