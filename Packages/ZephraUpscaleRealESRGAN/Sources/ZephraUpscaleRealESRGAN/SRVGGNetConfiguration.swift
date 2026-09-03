import Foundation

/// The shape of an SRVGGNetCompact: how wide the body is, how many convolutions it stacks, and
/// how many times larger the picture comes back.
///
/// Every published Real-ESRGAN "compact" model is this one network at different sizes, so the
/// architecture is a value rather than a class hierarchy. `generalX4v3` is the one Zephra
/// ships; a doll's house of the same shape is what the parity fixtures are dumped from.
public struct SRVGGNetConfiguration: Hashable, Sendable {
    /// Channels going in. Three, for RGB.
    public let inputChannels: Int
    /// Channels coming out. Three, for RGB.
    public let outputChannels: Int
    /// The width of the body's feature maps.
    public let features: Int
    /// How many convolution-and-activation pairs sit between the first pair and the last
    /// convolution. The reference calls this `num_conv`.
    public let convolutions: Int
    /// How many times larger each edge comes back.
    public let scale: Int

    /// Creates a configuration.
    public init(
        inputChannels: Int = 3,
        outputChannels: Int = 3,
        features: Int,
        convolutions: Int,
        scale: Int
    ) {
        self.inputChannels = inputChannels
        self.outputChannels = outputChannels
        self.features = features
        self.convolutions = convolutions
        self.scale = scale
    }

    /// `realesr-general-x4v3`: 64 features, 32 body convolutions, 4x.
    ///
    /// 1,213,296 parameters — 1792 in the first convolution, 64 in the first activation,
    /// 36,992 in each of the 32 body pairs, and 27,696 in the last convolution. That
    /// arithmetic is what says this is the right `num_conv` for the published checkpoint,
    /// which carries no configuration file of its own.
    public static let generalX4v3 = SRVGGNetConfiguration(
        features: 64, convolutions: 32, scale: 4)

    /// How many modules the body holds: the first convolution and activation, a pair for each
    /// body convolution, and the last convolution.
    public var bodyCount: Int { 2 + convolutions * 2 + 1 }
}
