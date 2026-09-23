import CoreGraphics
import Foundation
import ImageIO
import MLX
import Testing
import ZephraMLX
import ZephraTestSupport

@testable import QwenImage21

/// The reference-conditioned path against the reference, over the release's own weights.
///
/// `PipelineParityTests` pins text to picture. This pins the other half, and it is the half
/// 2.1 is mostly for: one condition picture goes through the vision tower as context *and*
/// through the autoencoder as latent tokens prepended to the noise, from one resize. A port
/// that showed the tower a picture the autoencoder never saw, or put the condition tokens in
/// the wrong place in the joint sequence, would still make a plausible picture from the prompt
/// alone — so the text-to-picture fixture cannot catch it, and this one can.
///
/// **The committed picture is already at the fitted size**, 1024 square, which is what
/// `calculate_dimensions(1024², 1)` gives. Both sides therefore resample nothing: PIL's
/// `resize` returns a copy when the size already matches, and a Core Graphics draw into a
/// bitmap of the picture's own size is a copy too. Committing it smaller would have put the
/// two runs a lanczos-against-Core-Graphics resample apart before the model saw anything, and
/// no tolerance on a latent would have meant much. `Tools/dump_pipeline_reference.py` refuses
/// to write a fixture at any other size, and the first expectation below checks the Swift fit
/// landed on the very bytes the reference read.
///
/// **This loads the release's 33 GB**, streamed, and skips without one.
@Suite("The whole pipeline makes the reference's picture from a reference picture")
struct PipelineReferenceParityTests {
    /// What `Tools/dump_pipeline_reference.py` ran, so the Swift side cannot drift from it.
    struct Reference: Decodable {
        let prompt: String
        let height: Int
        let width: Int
        let steps: Int
        let seed: Int
        let conditionWidth: Int
        let conditionHeight: Int
    }

    @Test(
        "two steps at 256 square over one condition picture land on the reference's own answer",
        .enabled(if: SnapshotUnderTest.qwenImage21.hasRelease),
        .timeLimit(.minutes(30)))
    func endToEnd() throws {
        let snapshot = try #require(SnapshotUnderTest.qwenImage21.release)
        let fixture = try Fixture.load("pipeline_reference")
        let reference = try JSONDecoder()
            .decode(Reference.self, from: try Fixture.json("pipeline_reference"))
        let png = try Self.picture("pipeline_reference")

        // Before the model: the fit this kit performs on those bytes changes nothing, so what
        // the pipeline reads is the committed picture and therefore the array the reference
        // was handed — the dumper checks that the PNG round trips losslessly, so the file's
        // own pixels stand in for it rather than a second 4.2 MB copy in the fixture. A
        // failure here is the resize or the premultiplied round trip, never the port.
        let fitted = try QwenImage21ReferencePicture.fitted(png)
        let decoded = try PipelineParityTests.pixels(
            of: png, width: reference.conditionWidth, height: reference.conditionHeight)
        #expect(fitted.shape == [reference.conditionHeight, reference.conditionWidth, 4])
        #expect(
            Fixture.maxAbsoluteDifference(fitted.reshaped(-1), decoded.reshaped(-1)) == 0,
            "the committed picture is already at the fitted size, so nothing is resampled")

        let pipeline = QwenImage21Pipeline()
        // Streamed, so the two layer stacks are read per pass rather than held: 33 GB resident
        // is more than the Macs this runs on have free beside a test host.
        try pipeline.loadModel(at: snapshot, streaming: QwenImage21Streaming(depth: 2))
        defer {
            // A streamed pass leaves the next pass's read-ahead scheduled as it ends, so the
            // reads are waited on before the weights are dropped.
            MLXRuntime.synchronize()
            pipeline.unloadModel()
        }

        let result = try pipeline.generate(
            QwenImage21Request(
                prompt: reference.prompt, width: reference.width, height: reference.height,
                steps: reference.steps, seed: UInt64(reference.seed), references: [png],
                noise: try #require(fixture["noise"])))

        let expected = try #require(fixture["latents"]).asType(.float32)
        let ours = result.latents.asType(.float32)
        #expect(ours.shape == expected.shape)
        // Relative, because a latent's scale is nothing in particular, and correlated as well,
        // because a port that scrambled an axis would still pass a mean.
        let scale = MLX.mean(MLX.abs(expected)).item(Float.self)
        let error = MLX.mean(MLX.abs(ours - expected)).item(Float.self)
        #expect(
            error / scale < Self.latentTolerance,
            Comment(rawValue: "mean |delta| \(error) against mean |latent| \(scale)"))
        #expect(PipelineParityTests.correlation(ours, expected) > Self.minimumCorrelation)

        #expect(result.width == reference.width && result.height == reference.height)
        let bytes = try PipelineParityTests.pixels(
            of: result.png, width: reference.width, height: reference.height)
        let all = try #require(fixture["pixels"]).reshaped([-1, 4]).asType(.float32)
        let channels = bytes.dim(1)
        if channels == 3 {
            #expect(all[.ellipsis, 3].min().item(Float.self) >= 250, "opaque only where the reference was")
        }
        let pixels = all[.ellipsis, ..<channels]
        let byteError = MLX.mean(MLX.abs(bytes - pixels)).item(Float.self)
        #expect(
            byteError < Self.pixelTolerance,
            Comment(rawValue: "mean byte difference \(byteError) on a range of 255"))
    }

    /// The finished latent's allowed mean absolute difference, relative to its mean magnitude.
    ///
    /// **Measured 0.047** (mean |delta| 0.060 against 1.276), Pearson 0.9988, on halcyon on
    /// 2026-09-22, and every part of it is bfloat16 rather than the port, which is why
    /// `PipelineParityTests`' two per cent cannot hold here. The joint sequence is 4374 tokens
    /// against that suite's 278, and one forward pass of the transformer over the reference's
    /// **own** inputs already lands 1.8 per cent from the reference, evenly over text,
    /// condition and target (1.7, 1.8, 1.4) — no block and no mask singled out. Two steps take
    /// that to 2.6 per cent; this port's own vision tower and decoder, both bfloat16 and both
    /// exact in float32 at this size, add 0.8; and the reference's bfloat16 condition encode
    /// against this port's float32 one (`ConditionLatentParityTests`) the last 1.3. A bit
    /// under twice the measurement, as the other suite's bounds are; a missing encoder stage,
    /// which is what this fixture recorded until the dumper's `mps` fold was fixed, read 0.996.
    static let latentTolerance: Float = 0.08

    /// Measured 0.99877; the 0.996-wrong latent above read 0.57.
    static let minimumCorrelation: Float = 0.995

    /// Mean byte difference allowed on a range of 255. **Measured 7.4**: two steps of a
    /// forty-step ladder decode to nearly pure noise, where a latent a few per cent away moves
    /// bytes further than it would in a finished picture. The broken fixture read 101.
    static let pixelTolerance: Float = 15

    /// The bytes of one committed PNG fixture, as a host would hand them to the pipeline.
    static func picture(_ name: String) throws -> Data {
        let url = try #require(
            Bundle.module.resourceURL?.appending(path: "Fixtures/\(name).png"),
            "the fixture bundle is missing")
        return try Data(contentsOf: url)
    }
}
