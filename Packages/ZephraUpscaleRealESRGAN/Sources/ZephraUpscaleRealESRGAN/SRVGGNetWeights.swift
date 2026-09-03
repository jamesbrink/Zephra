import Foundation
import MLX
import MLXNN
import ZephraCore

/// Turning a published checkpoint's tensors into the shapes this module tree holds.
///
/// One conversion, and it is mechanical: PyTorch stores a convolution kernel as
/// `[out, in, h, w]` and MLX as `[out, h, w, in]`, so every four-dimensional `.weight` is
/// transposed and everything else — the biases, and the PReLU alphas, which are one-dimensional
/// `.weight`s and must not be touched — goes through unchanged. No key is renamed: an MLX
/// `[UnaryLayer]` numbers its members `body.0`, `body.1`, … exactly as a torch `nn.ModuleList`
/// does.
///
/// `blending` is here so that the published denoise variant is a later argument rather than a
/// later rewrite. Real-ESRGAN ships `realesr-general-wdn-x4v3` as a second checkpoint of the
/// same shape, and the reference tool's denoise strength is a linear interpolation between the
/// two weight sets, not a change to the network. v1 never passes it.
public enum SRVGGNetWeights {
    /// The checkpoint's tensors under the names and in the layouts this tree wants.
    ///
    /// - Parameters:
    ///   - weights: the flat `body.N.weight` / `body.N.bias` state dict, already unwrapped.
    ///   - blending: a second checkpoint of the same shape to interpolate towards.
    ///   - fraction: how far towards `blending` to go, 0 leaving `weights` alone.
    public static func sanitized(
        _ weights: [String: MLXArray],
        blending: [String: MLXArray]? = nil,
        fraction: Float = 0
    ) -> [String: MLXArray] {
        let blended = mixed(weights, blending, fraction: fraction)
        return blended.reduce(into: [:]) { converted, entry in
            let (key, value) = entry
            if key.hasSuffix(".weight"), value.ndim == 4 {
                converted[key] = value.transposed(0, 2, 3, 1)
            } else {
                converted[key] = value
            }
        }
    }

    /// Fills `network` from `weights`, which must already be sanitized.
    ///
    /// `verify: .all` rather than a looser mode: the published tree is 101 tensors — 68 for
    /// the 34 convolutions and 33 PReLU alphas — that either all arrive or the checkpoint is
    /// not the one this architecture was written for, and a half-filled network produces a
    /// picture rather than an error.
    public static func load(
        into network: SRVGGNet, weights: [String: MLXArray]
    ) throws {
        do {
            try network.update(
                parameters: ModuleParameters.unflattened(weights), verify: .all)
        } catch {
            throw UpscaleError.weightsMissing(
                "the checkpoint does not match the network: \(error)")
        }
    }

    /// `weights` moved `fraction` of the way towards `other`, or `weights` when there is
    /// nothing to move towards.
    private static func mixed(
        _ weights: [String: MLXArray], _ other: [String: MLXArray]?, fraction: Float
    ) -> [String: MLXArray] {
        guard let other, fraction != 0 else { return weights }
        return weights.reduce(into: [:]) { mixed, entry in
            let (key, value) = entry
            guard let counterpart = other[key] else {
                mixed[key] = value
                return
            }
            mixed[key] = value * (1 - fraction) + counterpart * fraction
        }
    }
}
