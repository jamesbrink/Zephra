import Foundation

/// The shape of one BigVGAN generator: its widths and the kernels and strides of its
/// upsamplers, from the reference's `LTX2VocoderWithBWE` defaults, which the checkpoint's
/// tensors bear out.
public struct LTX2VocoderGeneratorLayout: Hashable, Sendable {
    /// Channels in: the mel's channels times its bins, 2 x 64.
    public var inputChannels: Int
    /// The first convolution's width, halved at every upsampler.
    public var hiddenChannels: Int
    /// Channels out: two, one per stereo channel.
    public var outputChannels: Int
    /// Each upsampler's kernel.
    public var kernels: [Int]
    /// Each upsampler's stride, whose product is the samples per mel frame.
    public var factors: [Int]

    public init(inputChannels: Int, hiddenChannels: Int, outputChannels: Int, kernels: [Int], factors: [Int]) {
        self.inputChannels = inputChannels
        self.hiddenChannels = hiddenChannels
        self.outputChannels = outputChannels
        self.kernels = kernels
        self.factors = factors
    }

    /// The first stage: 100 mel frames a second to 16 kHz, 160 samples a frame.
    public static let ltx25Vocoder = LTX2VocoderGeneratorLayout(
        inputChannels: 128, hiddenChannels: 1536, outputChannels: 2,
        kernels: [11, 4, 4, 4, 4, 4], factors: [5, 2, 2, 2, 2, 2])

    /// The bandwidth extender: 200 mel frames a second of the 16 kHz waveform to 48 kHz, 240
    /// samples a frame.
    public static let ltx25BandwidthExtender = LTX2VocoderGeneratorLayout(
        inputChannels: 128, hiddenChannels: 512, outputChannels: 2,
        kernels: [12, 11, 4, 4, 4], factors: [6, 5, 2, 2, 2])

    /// Samples one mel frame becomes.
    public var samplesPerFrame: Int { factors.reduce(1, *) }
}
