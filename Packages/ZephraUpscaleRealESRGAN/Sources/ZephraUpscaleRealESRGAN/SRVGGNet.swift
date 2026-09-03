import Foundation
import MLX
import MLXNN

/// SRVGGNetCompact: a plain stack of 3x3 convolutions that predicts the difference between a
/// nearest-neighbour enlargement and a real one.
///
/// The whole architecture is one flat list. A convolution widens three channels to `features`,
/// a per-channel PReLU follows it, `convolutions` more such pairs follow that, and a last
/// convolution widens to `outputChannels * scale * scale` so a pixel shuffle can trade those
/// channels for pixels. The nearest enlargement of the input is added to the result, which is
/// what makes the stack a residual predictor rather than a generator.
///
/// The list is `body` and its members are named `body.0` through `body.66`, which is exactly
/// what the published checkpoint calls them: an MLX `[UnaryLayer]` under `@ModuleInfo(key:)`
/// numbers its elements the way a torch `nn.ModuleList` does, so no key is renamed on the way
/// in — only the convolution kernels are transposed, in `SRVGGNetWeights`.
public final class SRVGGNet: Module {
    /// The flat stack, `body.0` through `body.<bodyCount - 1>`.
    @ModuleInfo(key: "body") public var body: [UnaryLayer]

    /// The shape this network was built to.
    public let configuration: SRVGGNetConfiguration

    /// Builds an unloaded network of `configuration`'s shape.
    public init(_ configuration: SRVGGNetConfiguration) {
        self.configuration = configuration
        var layers: [UnaryLayer] = [
            Conv2d(
                inputChannels: configuration.inputChannels,
                outputChannels: configuration.features,
                kernelSize: 3, padding: 1),
            PReLU(count: configuration.features),
        ]
        for _ in 0..<configuration.convolutions {
            layers.append(
                Conv2d(
                    inputChannels: configuration.features,
                    outputChannels: configuration.features,
                    kernelSize: 3, padding: 1))
            layers.append(PReLU(count: configuration.features))
        }
        layers.append(
            Conv2d(
                inputChannels: configuration.features,
                outputChannels: configuration.outputChannels * configuration.scale
                    * configuration.scale,
                kernelSize: 3, padding: 1))
        super.init()
        self._body.wrappedValue = layers
    }

    /// Enlarges `pixels`, `[batch, height, width, 3]` in 0...1, to
    /// `[batch, height * scale, width * scale, 3]`.
    ///
    /// The output is not clamped. Clamping belongs where the pixels become bytes, because the
    /// tiler's cross-fade is a weighted mean and a value clipped before the fade would move the
    /// seam rather than the pixel.
    public func callAsFunction(_ pixels: MLXArray) -> MLXArray {
        predicted(pixels) + NearestUpsample.apply(pixels, factor: configuration.scale)
    }

    /// The body chain and the pixel shuffle, without the residual: the difference the network
    /// predicts. Separated so a test can subtract it from the whole and check what is left is
    /// exactly a replication.
    func predicted(_ pixels: MLXArray) -> MLXArray {
        var activations = pixels
        for layer in body {
            activations = layer(activations)
        }
        return PixelShuffle.apply(activations, factor: configuration.scale)
    }
}
