import Foundation

/// The stage widths of both halves, and the small facts derived from them.
///
/// The two halves are **asymmetric** in 2.1, which is new: the encoder is built from `base_dim`
/// and the decoder from `decoder_base_dim`, 96 and 144 in the release, and a port that used one
/// for both would build a decoder a third too narrow and fail to load.
extension QwenImage21VAEConfiguration {
    /// `[dim * u for u in [1] + dim_mult]`: `[96, 96, 192, 384, 768, 768]` in the release, one
    /// entry more than there are stages, since a stage is a pair of them.
    ///
    /// Named beside the existing `encoderDims`, which is the multipliers alone; the encoder's
    /// tree needs the leading `base_dim` as well.
    var encoderStageDims: [Int] { ([1] + dimMult).map { baseDim * $0 } }

    /// `[dim * u for u in [dim_mult[-1]] + dim_mult[::-1]]`:
    /// `[1152, 1152, 1152, 576, 288, 144]` in the release.
    var decoderStageDims: [Int] {
        ([dimMult[dimMult.count - 1]] + dimMult.reversed()).map { decoderBaseDim * $0 }
    }

    /// Which stages the decoder unfolds time at, the encoder's list read backwards, which is
    /// what the reference computes as `temperal_downsample[::-1]`.
    var temperalUpsample: [Bool] { temperalDownsample.reversed() }

    /// Pixels a latent cell covers along each edge: `scale_factor_spatial`, 16, and also the
    /// count of stages that halve. The published file carries both and they agree; this reads
    /// the published one, so a configuration where they did not would load rather than differ
    /// silently from the release it came with.
    var spatialCompression: Int { scaleFactorSpatial }
}
