import Foundation
import ZephraCore

/// What a caller is holding when it asks for a picture to be made larger.
///
/// The two are a file in the library and a picture this session made, because those are the two
/// places the interface offers the action from. The store reduces either to a URL at once: the
/// parent's own record has to be read off the disk in both cases, and a picture that has not
/// been written yet has nothing to be made larger from.
public enum UpscaleSource: Hashable, Sendable {
    /// A file, chosen in the library grid or named by a menu command.
    case file(URL)
    /// A picture on the canvas, which may not have reached the disk yet.
    case image(GeneratedImage)

    /// Where the picture lives, or nil for one that has not been saved.
    public var fileURL: URL? {
        switch self {
        case .file(let url): url
        case .image(let image): image.fileURL
        }
    }
}
