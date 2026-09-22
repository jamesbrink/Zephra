import Foundation
import MLX
import Testing
import ZephraTestSupport

@testable import QwenImage21

/// The two autoencoders the VAE suites run against, and the one axis change between the
/// reference's tensors and this port's.
///
/// `vae.safetensors` is a doll's house whose weights are committed beside its activations, so
/// the architecture is pinned on a Mac with no release on it. `vae_real.safetensors` holds the
/// published autoencoder's own answers, and the suites that read it load the release's 1.35 GB
/// of float32 weights; those are gated on `hasRelease` and stated as a departure from "no test
/// loads model weights" in `PROVENANCE.md`. The doll's house alone cannot catch a scale read
/// off the wrong axis of a 96-channel stage, and unlike the transformer this model is small
/// enough to simply run.
enum VAEFixture {
    /// The reference holds a picture or a latent `[batch, channels, frames, height, width]`
    /// with one frame; this port holds `[batch, height, width, channels]` and has no frame
    /// axis at all. This is that change, and the only one.
    static func channelsLast(_ tensor: MLXArray) -> MLXArray {
        let (batch, channels) = (tensor.dim(0), tensor.dim(1))
        let (height, width) = (tensor.dim(3), tensor.dim(4))
        return tensor.reshaped([batch, channels, height, width]).transposed(0, 2, 3, 1)
    }

    /// The tensors of `fixture` whose names begin with `prefix`, with the prefix removed.
    static func weights(_ fixture: [String: MLXArray], under prefix: String)
        -> [String: MLXArray]
    {
        fixture.reduce(into: [:]) { kept, entry in
            guard entry.key.hasPrefix(prefix) else { return }
            kept[String(entry.key.dropFirst(prefix.count))] = entry.value
        }
    }

    /// The doll's house `Tools/dump_vae.py` builds: three stages, the middle one folding time,
    /// the last neither folding nor resizing, and the two halves at different widths.
    static let dollsHouse: QwenImage21VAEConfiguration = {
        let json = """
            {"_class_name": "AutoencoderKLQwenImage21", "attn_scales": [], "base_dim": 8,
             "decoder_base_dim": 12, "z_dim": 8, "dim_mult": [1, 2, 2], "num_res_blocks": 1,
             "temperal_downsample": [false, true], "dropout": 0.0, "is_residual": true,
             "in_channels": 4, "out_channels": 4, "patch_size": null,
             "scale_factor_spatial": 4, "scale_factor_temporal": 8,
             "latents_mean": [0, 0, 0, 0, 0, 0, 0, 0],
             "latents_std": [1, 1, 1, 1, 1, 1, 1, 1]}
            """
        // swiftlint:disable:next force_try
        return try! JSONDecoder().decode(
            QwenImage21VAEConfiguration.self, from: Data(json.utf8))
    }()

    /// The doll's-house autoencoder, filled from the fixture's own `model.*` tensors.
    static func dollsHouseAutoencoder(_ fixture: [String: MLXArray]) throws
        -> QwenImage21Autoencoder
    {
        let autoencoder = QwenImage21Autoencoder(dollsHouse)
        try autoencoder.load(weights: weights(fixture, under: "model."))
        return autoencoder
    }

    /// The release's own `vae/config.json`, and where it was read from.
    ///
    /// Config alone, so the suites that only compare names and shapes against a safetensors
    /// header never open 1.35 GB of weights.
    static func publishedConfiguration() throws -> (URL, QwenImage21VAEConfiguration) {
        let release = try #require(SnapshotUnderTest.qwenImage21.release)
        let configuration = try JSONDecoder().decode(
            QwenImage21VAEConfiguration.self,
            from: Data(contentsOf: release.appending(path: "vae/config.json"))
        ).validated()
        return (release, configuration)
    }

    /// The published autoencoder, read from the release this Mac has.
    ///
    /// Only the suites gated on `SnapshotUnderTest.qwenImage21.hasRelease` call this. The
    /// weights are evaluated here rather than left lazy, so what a parity test measures is the
    /// arithmetic and not a read that has not happened yet.
    static func published() throws -> (QwenImage21Autoencoder, QwenImage21VAEConfiguration) {
        let (release, configuration) = try publishedConfiguration()
        let autoencoder = QwenImage21Autoencoder(configuration)
        try autoencoder.load(
            weights: MLX.loadArrays(
                url: release.appending(path: "vae/\(VAEWeightKeyCoverageTests.file)")))
        eval(autoencoder.parameters())
        return (autoencoder, configuration)
    }
}
