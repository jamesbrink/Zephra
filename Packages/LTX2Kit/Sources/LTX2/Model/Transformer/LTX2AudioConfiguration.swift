import Foundation

/// The shape of the audio lane beside the video one, with LTX-2.5's values as the defaults.
///
/// The lane is 2048 wide — thirty-two heads of sixty-four — over 128-channel tokens, one per
/// latent audio frame at twenty-five a second (a 16 kHz mel at a hop of 160, compressed four
/// times), reading a 2048-wide text stream of its own. Its feed-forward keeps the biases the
/// video one dropped. The cross-modal attentions between the lanes are the audio lane's
/// heads wide on both sides.
public struct LTX2AudioConfiguration: Hashable, Sendable {
    /// Latent channels in and out of the lane: the eight channels of sixteen latent mel bins.
    public var channels: Int
    /// Attention heads in the audio lane and in both cross-modal attentions.
    public var heads: Int
    /// Width of one head.
    public var headDim: Int
    /// Width of the audio text conditioning the lane's cross-attention reads.
    public var crossAttentionDim: Int
    /// Whether the audio feed-forward's linears carry biases; true on LTX-2.5.
    public var feedForwardBias: Bool
    /// The seconds the rotary embedding measures a token's time against.
    public var ropeMaxSeconds: Double
    /// Latent audio frames a second.
    public var latentsPerSecond: Double

    public init(
        channels: Int = 128, heads: Int = 32, headDim: Int = 64, crossAttentionDim: Int = 2048,
        feedForwardBias: Bool = true, ropeMaxSeconds: Double = 20, latentsPerSecond: Double = 25
    ) {
        self.channels = channels
        self.heads = heads
        self.headDim = headDim
        self.crossAttentionDim = crossAttentionDim
        self.feedForwardBias = feedForwardBias
        self.ropeMaxSeconds = ropeMaxSeconds
        self.latentsPerSecond = latentsPerSecond
    }

    /// The lane's width.
    public var innerDim: Int { heads * headDim }
    /// The feed-forward's hidden width, four times the lane's.
    public var feedForwardDim: Int { innerDim * 4 }
    /// Rows the two cross-modal tables hold: scale and shift for each direction, and a gate.
    public static let crossModalRows = 5
}
