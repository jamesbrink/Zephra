import Foundation

/// What can be wrong with a `vae/config.json` before a weight is read.
public enum WanVAEConfigurationError: Error, Equatable, Sendable {
    /// `is_residual` is not true: the 2.1 layout, which this port does not carry.
    case notResidual
    /// `attn_scales` names a scale, asking for attention outside the mid block.
    case attentionOutsideMidBlock
    /// `latents_mean` or `latents_std` is not one value per latent channel.
    case statisticsDoNotMatchLatent(means: Int, stds: Int, channels: Int)
}
