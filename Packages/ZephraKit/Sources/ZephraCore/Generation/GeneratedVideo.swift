import Foundation

/// A finished clip: the encoded MP4, the PNG of its first frame, and how long it runs.
///
/// The poster is the clip's stand-in everywhere a picture is expected — the library's grid,
/// the record chunk, the thumbnail pipeline — so a video enters the app as an ordinary Zephra
/// PNG with the MP4 beside it. An audio track, when a model produces one, rides inside the
/// MP4; `hasAudio` only says it is there, for the record and the bench, and the player reads
/// the file's own tracks rather than this flag.
public struct GeneratedVideo: Hashable, Sendable {
    /// The first frame, encoded as PNG.
    public let poster: Data
    /// The whole clip, encoded as an MP4 container.
    public let mp4: Data
    /// How many frames the clip holds.
    public let frameCount: Int
    /// Frames per second the clip plays at.
    public let frameRate: Double
    /// Whether the MP4 carries an audio track beside the frames.
    public let hasAudio: Bool

    /// Creates a clip record.
    public init(poster: Data, mp4: Data, frameCount: Int, frameRate: Double, hasAudio: Bool = false) {
        self.poster = poster
        self.mp4 = mp4
        self.frameCount = frameCount
        self.frameRate = frameRate
        self.hasAudio = hasAudio
    }

    /// How long the clip plays, in seconds.
    public var seconds: Double { Double(frameCount) / frameRate }
}
