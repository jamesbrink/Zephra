import Foundation

/// The shape of the LTX-2 video transformer, with LTX-2.5's 22B values as the defaults.
///
/// Only the video lane is described: the audio lane's dimensions belong to the audio stream
/// that a video-only pack omits, and will arrive with it. Every default is the shipped
/// `config.json`'s; a doll's-house configuration for a parity test names its own.
public struct LTX2TransformerConfiguration: Hashable, Sendable {
    /// Latent channels in and out of the model.
    public var inChannels: Int
    /// Latent channels the output head projects back to.
    public var outChannels: Int
    /// Attention heads in the video lane.
    public var heads: Int
    /// Width of one head; `heads * headDim` is the stream's width.
    public var headDim: Int
    /// Width of the text conditioning the cross-attention reads.
    public var crossAttentionDim: Int
    /// How many transformer blocks the lane has.
    public var layers: Int
    /// Epsilon of every RMS and layer norm.
    public var normEps: Float
    /// Whether the feed-forward's two linears carry biases; false since LTX-2.5.
    public var feedForwardBias: Bool
    /// Base of the rotary frequency ladder.
    public var ropeTheta: Double
    /// The pixel-space extents positions are taken as a fraction of: frames, height, width.
    public var ropeMaxPositions: [Double]
    /// The sinusoid sees `sigma * timestepScale`.
    public var timestepScale: Float

    /// Creates a configuration; the defaults are LTX-2.5's.
    public init(
        inChannels: Int = 128,
        outChannels: Int = 128,
        heads: Int = 32,
        headDim: Int = 128,
        crossAttentionDim: Int = 4096,
        layers: Int = 48,
        normEps: Float = 1e-6,
        feedForwardBias: Bool = false,
        ropeTheta: Double = 10000,
        ropeMaxPositions: [Double] = [20, 2048, 2048],
        timestepScale: Float = 1000
    ) {
        self.inChannels = inChannels
        self.outChannels = outChannels
        self.heads = heads
        self.headDim = headDim
        self.crossAttentionDim = crossAttentionDim
        self.layers = layers
        self.normEps = normEps
        self.feedForwardBias = feedForwardBias
        self.ropeTheta = ropeTheta
        self.ropeMaxPositions = ropeMaxPositions
        self.timestepScale = timestepScale
    }

    /// The stream's width.
    public var innerDim: Int { heads * headDim }
    /// The feed-forward's hidden width, four times the stream's.
    public var feedForwardDim: Int { innerDim * 4 }
    /// Modulation rows a block's table holds: shift, scale and gate for the self-attention, the
    /// feed-forward, and the cross-attention's queries.
    public static let blockModulationRows = 9
    /// Rows the prompt table holds: shift and scale for the cross-attention's keys and values.
    public static let promptModulationRows = 2
}
