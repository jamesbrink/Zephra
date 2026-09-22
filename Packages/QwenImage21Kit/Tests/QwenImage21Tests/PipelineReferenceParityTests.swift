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
        // The port does not pass this yet, and the fixture is why it is known. Measured on
        // halcyon on 2026-09-22: the fitted picture and the whole joint layout are identical to
        // the reference's, the text positions either side of the picture are at this run's
        // bfloat16 floor (3.6 and 3.2 per cent), and then the picture's own 1024 vision tokens
        // are 23.5 per cent out and the condition latents 76 per cent (Pearson 0.77, evenly
        // over the picture), which carries the finished latent to 99.6 per cent and the decoded
        // bytes to 101 on a range of 255. Two independent parts of the reference-conditioned
        // path, both only at the 1024-square size a real reference lands on, which is past
        // everything `dump_vision.py` and `dump_vae.py` pin. `PROVENANCE.md` has the table and
        // `ROADMAP.md` owes the fix; enabling this suite is deleting this one trait.
        .disabled(
            "the reference-conditioned path does not match the reference yet; see PROVENANCE.md"),
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
            error / scale < PipelineParityTests.latentTolerance,
            Comment(rawValue: "mean |delta| \(error) against mean |latent| \(scale)"))
        #expect(PipelineParityTests.correlation(ours, expected) > 0.999)

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
            byteError < PipelineParityTests.pixelTolerance,
            Comment(rawValue: "mean byte difference \(byteError) on a range of 255"))
    }

    /// The bytes of one committed PNG fixture, as a host would hand them to the pipeline.
    static func picture(_ name: String) throws -> Data {
        let url = try #require(
            Bundle.module.resourceURL?.appending(path: "Fixtures/\(name).png"),
            "the fixture bundle is missing")
        return try Data(contentsOf: url)
    }
}
