import Foundation

/// What one generation hands back: the clip's frames and its first frame as a PNG, both from
/// the same decode, so the poster is exactly the frame a player shows first, and its sound
/// when the model made any.
public struct LTX2Clip: Sendable {
    /// Every frame, as RGBA8.
    public let video: LTX2Video
    /// The first frame, encoded as PNG.
    public let poster: Data
    /// The clip's sound, or nil on a video-only model.
    public let audio: LTX2Audio?

    public init(video: LTX2Video, poster: Data, audio: LTX2Audio? = nil) {
        self.video = video
        self.poster = poster
        self.audio = audio
    }
}
