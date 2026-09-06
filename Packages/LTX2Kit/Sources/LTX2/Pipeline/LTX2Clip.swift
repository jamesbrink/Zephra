import Foundation

/// What one generation hands back: the clip's frames and its first frame as a PNG, both from
/// the same decode, so the poster is exactly the frame a player shows first.
public struct LTX2Clip: Sendable {
    /// Every frame, as RGBA8.
    public let video: LTX2Video
    /// The first frame, encoded as PNG.
    public let poster: Data

    public init(video: LTX2Video, poster: Data) {
        self.video = video
        self.poster = poster
    }
}
