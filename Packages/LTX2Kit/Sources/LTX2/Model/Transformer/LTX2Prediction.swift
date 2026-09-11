import Foundation
import MLX

/// What one step of the transformer predicts: the video's velocity, and the audio's when the
/// tree has the lane and the step handed it a stream.
public struct LTX2Prediction {
    /// `[batch, tokens, outChannels]`.
    public let video: MLXArray
    /// `[batch, audioTokens, audioChannels]`, or nil on a video-only run.
    public let audio: MLXArray?

    public init(video: MLXArray, audio: MLXArray?) {
        self.video = video
        self.audio = audio
    }
}
