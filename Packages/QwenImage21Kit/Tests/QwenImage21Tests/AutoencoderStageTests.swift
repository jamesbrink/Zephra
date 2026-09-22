import Foundation
import MLX
import MLXNN
import Testing
import ZephraTestSupport

@testable import QwenImage21

/// Each stage of the published autoencoder against what the reference handed on at that point.
///
/// `AutoencoderTests` says whether the two agree; this says **where** they stop agreeing. The
/// fixture carries the output of every stage of both halves over one small input, taken with
/// forward hooks, so a wrong average-down shortcut reads as "down_blocks.1 differs and
/// down_blocks.0 does not" instead of as one number at the end.
/// The comparison is **relative**, unlike the parity suites' -- an activation is not a pixel.
/// `up_blocks.3` reaches a magnitude of 2128 in the middle of the decoder, so an absolute
/// tolerance fit for a -1 to 1 picture would fail there on nothing. Every stage of both halves
/// measures 3e-6 relative, uniformly, which is float32 accumulating and not a disagreement;
/// 1e-4 leaves thirty times that.
@Suite("the published autoencoder agrees with the reference stage by stage")
struct AutoencoderStageTests {
    static let tolerance: Float = 1e-4

    @Test(
        "every encoder stage hands on what the reference's did",
        .enabled(if: SnapshotUnderTest.qwenImage21.hasRelease))
    func encoderStages() throws {
        let fixture = try Fixture.load("vae_real")
        let (autoencoder, _) = try VAEFixture.published()
        let encoder = autoencoder.encoder

        var x = encoder.convIn(VAEFixture.channelsLast(try #require(fixture["bisect.picture"])))
        try expect(x, matches: fixture, "tap.encoder.conv_in")
        for (index, block) in encoder.downBlocks.enumerated() {
            x = block(x)
            try expect(x, matches: fixture, "tap.encoder.down_blocks.\(index)")
        }
        x = encoder.midBlock(x)
        try expect(x, matches: fixture, "tap.encoder.mid_block")
        x = encoder.convOut(silu(encoder.normOut(x)))
        try expect(x, matches: fixture, "tap.encoder.conv_out")
        try expect(autoencoder.quantConv(x), matches: fixture, "tap.quant_conv")
    }

    @Test(
        "every decoder stage hands on what the reference's did",
        .enabled(if: SnapshotUnderTest.qwenImage21.hasRelease))
    func decoderStages() throws {
        let fixture = try Fixture.load("vae_real")
        let (autoencoder, _) = try VAEFixture.published()
        let decoder = autoencoder.decoder

        var x = autoencoder.postQuantConv(
            VAEFixture.channelsLast(try #require(fixture["bisect.latent"])))
        try expect(x, matches: fixture, "tap.post_quant_conv")
        x = decoder.convIn(x)
        try expect(x, matches: fixture, "tap.decoder.conv_in")
        x = decoder.midBlock(x)
        try expect(x, matches: fixture, "tap.decoder.mid_block")
        for (index, block) in decoder.upBlocks.enumerated() {
            x = block(x)
            try expect(x, matches: fixture, "tap.decoder.up_blocks.\(index)")
        }
        // The reference's clamp lives in `_decode`, past the decoder module, so the tap is
        // unclamped and this compares the same thing.
        try expect(
            decoder.convOut(silu(decoder.normOut(x))), matches: fixture, "tap.decoder.conv_out")
    }

    private func expect(_ x: MLXArray, matches fixture: [String: MLXArray], _ name: String)
        throws
    {
        let expected = VAEFixture.channelsLast(try #require(fixture[name]))
        #expect(x.shape == expected.shape, Comment(rawValue: name))
        let scale = MLX.max(MLX.abs(expected)).item(Float.self)
        let relative = Fixture.maxAbsoluteDifference(x, expected) / Swift.max(scale, 1e-6)
        #expect(
            relative < Self.tolerance,
            Comment(rawValue: "\(name): \(relative) relative, at a magnitude of \(scale)"))
    }
}
