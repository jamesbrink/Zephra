import Foundation

/// What can be wrong with a transformer's configuration before a weight is read.
public enum WanTransformerConfigurationError: Error, Equatable, Sendable {
    /// `image_dim` or `added_kv_proj_dim` is set: the CLIP image path of the Wan 2.1
    /// image-to-video models, which this port does not build.
    case imageConditioningNotSupported
    /// `qk_norm` names a normalisation other than `rms_norm_across_heads`.
    case unsupportedQKNorm(String?)
}
