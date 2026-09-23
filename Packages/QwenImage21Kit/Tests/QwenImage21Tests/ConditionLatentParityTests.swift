import Foundation
import MLX
import Testing
import ZephraMLX
import ZephraTestSupport

@testable import QwenImage21

/// The condition picture's latents at the size a real reference picture lands on.
///
/// `AutoencoderRoundTripTests` and `vae_real.safetensors` pin this autoencoder at a 64-pixel
/// picture, which is a 4 by 4 latent grid. That is every stage of the encoder and none of its
/// sizes: `QwenImage21AvgDown`, the shortcut around each stage, folds the frame axis and the
/// two spatial offsets into the channel axis, and what the fold costs depends entirely on how
/// large the tensor is. A 1024-square reference -- which is what `calculate_dimensions` brings
/// every condition image to, whatever it arrived as -- runs that fold at 96 channels by 512
/// square and again at 192 by 256, and **`mps` returns zeros for both** (`PROVENANCE.md`).
///
/// So this suite exists for the one thing the small fixture cannot say: that the encoder is
/// right at the only size the pipeline ever asks it for. It loads the autoencoder alone, a
/// gigabyte rather than the pipeline's 33, and runs in seconds.
@Suite("The condition picture's latents are the reference's at the size a reference lands on")
struct ConditionLatentParityTests {
    @Test(
        "a 1024-square reference encodes to the reference's own condition tokens",
        .enabled(if: SnapshotUnderTest.qwenImage21.hasRelease),
        .timeLimit(.minutes(10)))
    func conditionLatents() throws {
        let snapshot = try #require(SnapshotUnderTest.qwenImage21.release)
        let configuration = try QwenImage21Configuration(readingFrom: snapshot)
        let autoencoder = QwenImage21Autoencoder(configuration.vae)
        try autoencoder.load(
            weights: try SafetensorsShards.weights(
                in: snapshot.appending(
                    path: QwenImage21Configuration.Component.vae.directoryName)))

        let picture = try QwenImage21ReferencePicture.fitted(
            try PipelineReferenceParityTests.picture("pipeline_reference"))
        let ours = QwenImage21Pipeline.conditionTokens(
            of: picture, autoencoder: autoencoder,
            normalization: QwenImage21LatentNormalization(configuration.vae),
            activation: .float32)
        let expected = try #require(try Fixture.load("pipeline_reference")["condition"])

        #expect(ours.shape == expected.shape, "4096 tokens of 64 channels, a 64 by 64 grid")
        let scale = MLX.mean(MLX.abs(expected)).item(Float.self)
        let error = MLX.mean(MLX.abs(ours.asType(.float32) - expected)).item(Float.self)
        // Measured 0.0106 on halcyon on 2026-09-22, Pearson below. The reference runs this
        // encoder in bfloat16 on `mps` and this port in float32, so what is left is the
        // reference's own rounding: against a float32 CPU encode the port lands at 3.3e-6.
        // Three per cent is loose enough for that and nowhere near loose enough for a stage of
        // the encoder going missing, which is what this is here to catch: that reads 0.68.
        #expect(
            error / scale < 0.03,
            Comment(rawValue: "mean |delta| \(error) against mean |latent| \(scale)"))
        #expect(PipelineParityTests.correlation(ours.asType(.float32), expected) > 0.999)
    }
}
