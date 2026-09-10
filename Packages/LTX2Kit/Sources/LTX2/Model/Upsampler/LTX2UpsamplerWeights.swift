import Foundation
import MLX

/// Converts the published upsampler weights into the names its module tree uses.
///
/// One conversion, and the smallest of the kit's: the pack prefixes every tensor of
/// `spatial_upscaler_x2_v1_1.safetensors` with the file's own stem, and under it the names are
/// the reference's module paths word for word (`initial_conv`, `res_blocks.N.norm1`,
/// `upsampler.0`, `post_upsample_res_blocks.N`, `final_conv`), which are the tree's. Kernels
/// are already channels-last, `[out, kd, kh, kw, in]` and `[out, kh, kw, in]`, so nothing is
/// transposed, and a fixture dumped from PyTorch is written in that order too, so one loader
/// serves both. Anything under another prefix is dropped rather than refused, as the
/// autoencoder's sanitizers do, so a loader holding several files at once loses nothing.
public enum LTX2UpsamplerWeights {
    /// The prefix every tensor of the pack's upsampler file carries.
    public static let prefix = "spatial_upscaler_x2_v1_1."

    /// The upsampler's weights, renamed for its module tree.
    public static func sanitized(_ weights: [String: MLXArray]) -> [String: MLXArray] {
        LTX2VAEWeights.stripped(weights, of: prefix)
    }

    /// What the pack's file calls the parameter at `path` in the module tree.
    public static func checkpointName(of path: String) -> String {
        prefix + path
    }
}
