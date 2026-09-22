import CoreGraphics
import Foundation
import ImageIO
import MLX
import Testing
import ZephraMLX
import ZephraTestSupport

@testable import QwenImage21

/// The whole port against the whole reference, over the release's own weights.
///
/// Every other suite here pins one component against one input. This one runs the pipeline end
/// to end — template, tokenizer, vision-language encoder, joint layout, rotary, prefix cache,
/// schedule, Euler step and autoencoder — and compares what came out with what
/// `Tools/dump_pipeline.py` got from `diffusers` for the same prompt and the same noise. It is
/// the one test that says the port makes the reference's picture rather than a plausible one.
///
/// **The noise is handed in.** `MLXRandom` is not a `torch.Generator`, so the same seed is a
/// different draw and no tolerance on a picture would mean anything; the fixture carries the
/// packed latent the reference drew and `QwenImage21Request.noise` injects it, so both loops
/// walk the same ladder from the same place. `PROVENANCE.md` states it.
///
/// **This loads the release's 33 GB**, streamed, which is the second place this kit departs
/// from "no test loads model weights" and the one that earns it. It is one test rather than
/// two for the same reason: the load is the expensive part, so the latent and the picture it
/// decodes to are judged in one run. It skips without a release.
@Suite("The whole pipeline makes the reference's picture")
struct PipelineParityTests {
    /// What `Tools/dump_pipeline.py` ran, so the Swift side cannot drift from it.
    struct Reference: Decodable {
        let prompt: String
        let height: Int
        let width: Int
        let steps: Int
        let seed: Int
    }

    @Test(
        "two steps at 256 square land on the reference's own latent and its picture",
        .enabled(if: SnapshotUnderTest.qwenImage21.hasRelease),
        .timeLimit(.minutes(30)))
    func endToEnd() throws {
        let snapshot = try #require(SnapshotUnderTest.qwenImage21.release)
        let fixture = try Fixture.load("pipeline")
        let reference = try JSONDecoder().decode(Reference.self, from: try Fixture.json("pipeline"))

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
                steps: reference.steps, seed: UInt64(reference.seed),
                noise: try #require(fixture["noise"])))

        let expected = try #require(fixture["latents"]).asType(.float32)
        let ours = result.latents.asType(.float32)
        #expect(ours.shape == expected.shape)
        // Relative, because a latent's scale is nothing in particular. The reference runs in
        // bfloat16 too, so what is measured is two orderings of the same arithmetic rather
        // than one of them being right.
        let scale = MLX.mean(MLX.abs(expected)).item(Float.self)
        let error = MLX.mean(MLX.abs(ours - expected)).item(Float.self)
        #expect(
            error / scale < Self.latentTolerance,
            Comment(rawValue: "mean |delta| \(error) against mean |latent| \(scale)"))
        // And they are the same latent rather than two latents of the same size: a port that
        // scrambled an axis would still pass a mean.
        #expect(Self.correlation(ours, expected) > 0.999)

        #expect(result.width == reference.width && result.height == reference.height)
        let bytes = try Self.rgba(of: result.png, width: reference.width, height: reference.height)
        let pixels = try #require(fixture["pixels"]).reshaped(-1).asType(.float32)
        #expect(bytes.dim(0) == pixels.dim(0), "four channels a pixel on both sides")
        let byteError = MLX.mean(MLX.abs(bytes - pixels)).item(Float.self)
        #expect(
            byteError < Self.pixelTolerance,
            Comment(rawValue: "mean byte difference \(byteError) on a range of 255"))
    }

    /// The mean absolute difference the finished latent is allowed, as a fraction of the
    /// reference latent's own mean magnitude.
    ///
    /// **Measured 0.0087** — a mean delta of 0.0082 against a mean latent magnitude of 0.943 —
    /// with a Pearson correlation of 0.99996. Both sides run bfloat16 activations over the same
    /// weights, so what is left is rounding compounded through 32 blocks and two steps rather
    /// than a difference in the arithmetic. Two per cent is a bit over twice the measurement,
    /// which leaves room for MLX and torch disagreeing about a reduction order and none for a
    /// model that is wrong.
    static let latentTolerance: Float = 0.02

    /// The mean byte a decoded pixel is allowed to differ by, on a range of 255.
    ///
    /// **Measured 0.70**, which is a quarter of one per cent. Two steps of a forty-step ladder
    /// is nearly pure noise, so this is about the autoencoder, the channel order and the
    /// rounding to a byte rather than about the picture.
    static let pixelTolerance: Float = 2

    /// The Pearson correlation of two tensors, flattened.
    static func correlation(_ a: MLXArray, _ b: MLXArray) -> Float {
        let (x, y) = (a.reshaped(-1), b.reshaped(-1))
        let (dx, dy) = (x - MLX.mean(x), y - MLX.mean(y))
        let denominator = MLX.sqrt(MLX.sum(dx * dx) * MLX.sum(dy * dy))
        return (MLX.sum(dx * dy) / denominator).item(Float.self)
    }

    /// A PNG this pipeline wrote, back as the straight-alpha bytes it was written from.
    ///
    /// The provider's own bytes, never a redraw: Core Graphics has no straight-alpha context,
    /// so drawing the image into one to read it back would premultiply the very channel under
    /// test.
    static func rgba(of png: Data, width: Int, height: Int) throws -> MLXArray {
        let source = try #require(CGImageSourceCreateWithData(png as CFData, nil))
        let image = try #require(CGImageSourceCreateImageAtIndex(source, 0, nil))
        #expect(image.width == width && image.height == height)
        #expect(image.alphaInfo == .last, "straight alpha, never premultiplied")
        return MLXArray([UInt8](try #require(image.dataProvider?.data) as Data)).asType(.float32)
    }
}
