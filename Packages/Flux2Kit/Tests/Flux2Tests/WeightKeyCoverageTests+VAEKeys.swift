import Foundation

@testable import Flux2

/// What the autoencoder must carry, derived from `vae/config.json` alone.
///
/// Both towers are stated because the editing path encodes a reference image, so neither half is
/// dead weight. The shapes are left to the spot checks in the suite: the names are what a
/// miscounted stage or a missing shortcut shows up in.
extension WeightKeyCoverageTests {
    static func expectedAutoencoderKeys(_ configuration: Flux2VAEConfiguration) -> Set<String> {
        var keys = pair("quant_conv").union(pair("post_quant_conv"))
        // The latent normalisation, held as batch-norm running statistics rather than as the
        // scaling and shift factor every other diffusers autoencoder uses. No affine pair.
        keys.formUnion(["bn.running_mean", "bn.running_var", "bn.num_batches_tracked"])
        keys.formUnion(encoderKeys(configuration))
        keys.formUnion(decoderKeys(configuration))
        return keys
    }

    private static func encoderKeys(_ configuration: Flux2VAEConfiguration) -> Set<String> {
        let channels = configuration.blockOutChannels
        var keys = pair("encoder.conv_in")
            .union(pair("encoder.conv_norm_out"))
            .union(pair("encoder.conv_out"))
            .union(midBlockKeys("encoder"))

        for (stage, outChannels) in channels.enumerated() {
            let prefix = "encoder.down_blocks.\(stage)"
            let inChannels = channels[max(stage - 1, 0)]
            for block in 0..<configuration.layersPerBlock {
                keys.formUnion(
                    resnetKeys(
                        "\(prefix).resnets.\(block)",
                        shortcut: block == 0 && inChannels != outChannels))
            }
            // Every stage but the last halves the resolution on its way out.
            if stage < channels.count - 1 {
                keys.formUnion(pair("\(prefix).downsamplers.0.conv"))
            }
        }
        return keys
    }

    private static func decoderKeys(_ configuration: Flux2VAEConfiguration) -> Set<String> {
        let channels = configuration.blockOutChannels.reversed().map { $0 }
        var keys = pair("decoder.conv_in")
            .union(pair("decoder.conv_norm_out"))
            .union(pair("decoder.conv_out"))
            .union(midBlockKeys("decoder"))

        for (stage, outChannels) in channels.enumerated() {
            let prefix = "decoder.up_blocks.\(stage)"
            let inChannels = channels[max(stage - 1, 0)]
            // One more residual block per stage than the encoder has, which is what
            // `layers_per_block` means on the way up.
            for block in 0...configuration.layersPerBlock {
                keys.formUnion(
                    resnetKeys(
                        "\(prefix).resnets.\(block)",
                        shortcut: block == 0 && inChannels != outChannels))
            }
            if stage < channels.count - 1 {
                keys.formUnion(pair("\(prefix).upsamplers.0.conv"))
            }
        }
        return keys
    }

    /// Two residual blocks with a self-attention between them, at the coarsest resolution.
    private static func midBlockKeys(_ tower: String) -> Set<String> {
        var keys = resnetKeys("\(tower).mid_block.resnets.0", shortcut: false)
            .union(resnetKeys("\(tower).mid_block.resnets.1", shortcut: false))
        let attention = "\(tower).mid_block.attentions.0"
        for name in ["group_norm", "to_q", "to_k", "to_v", "to_out.0"] {
            keys.formUnion(pair("\(attention).\(name)"))
        }
        return keys
    }

    /// Norm, convolution, norm, convolution, and a 1x1 shortcut when the width changes.
    private static func resnetKeys(_ prefix: String, shortcut: Bool) -> Set<String> {
        var keys = pair("\(prefix).norm1")
            .union(pair("\(prefix).conv1"))
            .union(pair("\(prefix).norm2"))
            .union(pair("\(prefix).conv2"))
        if shortcut { keys.formUnion(pair("\(prefix).conv_shortcut")) }
        return keys
    }

    /// A weight and its bias. Everything in this autoencoder has both.
    private static func pair(_ name: String) -> Set<String> {
        ["\(name).weight", "\(name).bias"]
    }
}
