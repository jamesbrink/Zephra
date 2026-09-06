import Foundation

/// What a backend hands back from one generation: a picture, or a clip with its poster.
///
/// One type rather than two protocol methods, because the engine runs every family through
/// the same queue, timer and cancellation check and only the last step — what to publish and
/// what to write — reads the kind. An image family wraps its PNG in `.image` and is otherwise
/// untouched by video existing.
public enum GeneratedMedia: Hashable, Sendable {
    /// One finished picture, as PNG bytes.
    case image(png: Data)
    /// A finished clip, with its first frame as the picture the library indexes.
    case video(GeneratedVideo)

    /// The picture that stands for this result: the image itself, or the clip's poster.
    public var posterPNG: Data {
        switch self {
        case .image(let png): return png
        case .video(let video): return video.poster
        }
    }
}
