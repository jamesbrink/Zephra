import Foundation

/// What a strip of reference pictures may come to, wherever one is assembled.
///
/// One place, because four sites enforce it: the store refuses a picture past the budget where a
/// person can see the refusal, `ModelCapabilities.clamp` guards a request composed anywhere else,
/// the PNG record files at most this many numbered chunks, and a session holds at least this many
/// blobs so ten pictures announced one at a time all survive until the request that names them.
public enum ReferenceLimits {
    /// The most pictures any model may be handed, whatever its own count says.
    ///
    /// Ten, because the numbered PNG keywords stop there (`zephra:reference.10`), and because the
    /// per-picture cap stays at 1024 pixels an edge: a pipeline that reads several pictures
    /// resizes every one of them to about a megapixel anyway, so a smaller cap would throw away
    /// detail the model reads.
    public static let maximumPictures = 10

    /// The most the whole strip may weigh, as PNG.
    ///
    /// 24 MiB is ten pictures at the couple of megabytes an encoded 1024-pixel PNG runs to, with
    /// room for the photographic ones that compress badly. A budget rather than a second
    /// per-picture cap, because what costs is the sum: it rides in every queue entry, every PNG
    /// record and every blob transfer.
    public static let maximumTotalBytes = 24 << 20

    /// `pictures` with the ones past the budget dropped from the end, which is the order they
    /// were added in, so the picture chosen first is the picture that survives.
    public static func withinBudget(_ pictures: [ReferencePicture]) -> [ReferencePicture] {
        var kept: [ReferencePicture] = []
        var total = 0
        for picture in pictures {
            total += picture.data.count
            guard total <= maximumTotalBytes else { break }
            kept.append(picture)
        }
        return kept
    }

    /// Whether `pictures` fit both limits, which is what an adoption asks before it takes them.
    public static func fit(_ pictures: [ReferencePicture]) -> Bool {
        pictures.count <= maximumPictures
            && pictures.reduce(0) { $0 + $1.data.count } <= maximumTotalBytes
    }
}
