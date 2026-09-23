import Foundation
import MLX
import Testing

@testable import QwenImage21

/// What the pipeline works out before a weight is touched: how many tokens a size is, what the
/// schedule's shift comes to for them, and where the prediction's tail begins.
///
/// None of this needs a model, and all of it is silent when wrong. A target token count one out
/// bends the schedule by the wrong amount; a tail slice one out hands the Euler step a row of
/// text.
@Suite("The pipeline's arithmetic between a size and a step")
struct PipelineLayoutTests {
    private static let scheduler = QwenImage21SchedulerConfiguration()

    /// The layout a text-only request of `width` by `height` builds, over a prompt of
    /// `promptTokens` states with no picture in it.
    static func textOnlyLayout(
        width: Int, height: Int, promptTokens: Int, scale: Int = 16
    ) throws -> QwenImage21JointLayout {
        let target = QwenImage21ImageShape(height: height / scale, width: width / scale)
        let slots =
            [Bool](repeating: false, count: promptTokens)
            + [Bool](
                repeating: true,
                count: target.tokenCount / QwenImage21JointLayout.tokensPerSlot)
        return try QwenImage21JointLayout(imageSlots: slots, shapes: [target])
    }

    @Test("a 1024-square picture is 4096 latent tokens and 1024 appended vision-language slots")
    func targetTokens() throws {
        let layout = try Self.textOnlyLayout(width: 1024, height: 1024, promptTokens: 20)
        #expect(layout.targetTokenCount == 4096)
        #expect(layout.encoderTokenCount == 20)
        #expect(layout.prefixLength == 20)
        #expect(layout.sequenceLength == 20 + 4096)
        #expect(layout.shapes == [QwenImage21ImageShape(height: 64, width: 64)])
        // Every latent token is a target token, and they are the sequence's trailing run.
        #expect(layout.targetTokenMask.filter { $0 }.count == 4096)
        #expect(layout.targetTokenMask[20...].allSatisfy { $0 })
    }

    @Test("the shift the schedule is bent by is the fixture's, for the size the pipeline counts")
    func shiftForTheTargetAlone() throws {
        let fixture = try Fixture.load("scheduler")
        let layout = try Self.textOnlyLayout(width: 1024, height: 1024, promptTokens: 20)
        let mu = QwenImage21DynamicShift.mu(
            imageSequenceLength: layout.targetTokenCount, configuration: Self.scheduler)
        let expected = try #require(fixture["steps40.tokens4096.mu"]).item(Float.self)
        #expect(abs(Float(mu) - expected) < 1e-6)
        #expect(abs(mu - 0.693548) < 1e-6)
    }

    @Test("a reference picture lengthens the prefix and never the target the shift counts")
    func referenceDoesNotMoveTheShift() throws {
        // One 512 x 512 reference is 32 x 32 latent cells, which is 1024 latent tokens and so
        // 256 vision-language slots inside the prompt.
        let reference = QwenImage21ImageShape(height: 32, width: 32)
        let target = QwenImage21ImageShape(height: 64, width: 64)
        var slots = [Bool](repeating: false, count: 30)
        slots.replaceSubrange(5..<5, with: [Bool](repeating: true, count: 256))
        slots += [Bool](repeating: true, count: 1024)
        let layout = try QwenImage21JointLayout(
            imageSlots: slots, shapes: [reference, target])

        #expect(layout.targetTokenCount == 4096, "the shift counts the picture being made")
        #expect(layout.prefixLength == 30 + 1024)
        #expect(layout.sequenceLength == 30 + 1024 + 4096)
        let mu = QwenImage21DynamicShift.mu(
            imageSequenceLength: layout.targetTokenCount, configuration: Self.scheduler)
        #expect(abs(mu - 0.693548) < 1e-6, "not the joint sequence's own length")
    }

    @Test("the prefill's prediction is sliced to the trailing target tokens")
    func tailSlice() throws {
        let layout = try Self.textOnlyLayout(width: 64, height: 64, promptTokens: 7)
        // One row per joint position, carrying its own index, which is what the reference's
        // `noise_pred[:, -latents.size(1):]` has to pick the last `targetTokenCount` of.
        let whole = MLXArray(0..<Int32(layout.sequenceLength))
            .reshaped(1, layout.sequenceLength, 1)
        let sliced = whole[0..., (whole.dim(1) - layout.targetTokenCount)...]
        #expect(sliced.dim(1) == layout.targetTokenCount)
        #expect(sliced[0, 0, 0].item(Int32.self) == Int32(layout.prefixLength))
        #expect(
            sliced[0, layout.targetTokenCount - 1, 0].item(Int32.self)
                == Int32(layout.sequenceLength - 1))
        // A cached step answers only those tokens, so the same slice is a no-op there.
        let cached = whole[0..., layout.prefixLength...]
        #expect(cached[0..., (cached.dim(1) - layout.targetTokenCount)...].dim(1) == cached.dim(1))
    }

    @Test("unpacking a latent is the inverse of packing it, channels last for the autoencoder")
    func unpackingRoundTrips() {
        let grid = MLXArray(0..<Int32(2 * 3 * 4)).reshaped(1, 2, 3, 4).asType(.float32)
        let tokens = QwenImage21LatentPacking.tokens(grid)
        #expect(tokens.shape == [1, 12, 2])
        let back = QwenImage21Pipeline.unpacked(tokens, height: 3, width: 4)
        #expect(back.shape == [1, 3, 4, 2], "channels last, which is what the decoder reads")
        #expect(Fixture.maxAbsoluteDifference(back.transposed(0, 3, 1, 2), grid) == 0)
    }

    @Test("guidance runs a second forward only when there is a negative prompt to run it on")
    func guidanceGate() {
        func request(_ guidance: Double, _ negative: String) -> QwenImage21Request {
            QwenImage21Request(
                prompt: "a cat", negativePrompt: negative, width: 1024, height: 1024,
                steps: 40, guidance: guidance, seed: 1)
        }
        #expect(!request(1, "blurry").usesGuidance, "the reference's own default is 1.0")
        #expect(!request(4, "").usesGuidance)
        #expect(request(4, "blurry").usesGuidance)
    }

    @Test("the snapshot layout names the packer's stamp first and the release's own index")
    func snapshotLayout() {
        // The packer writes `quantization.json` last, so a build stopped part-way reads as
        // incomplete rather than half-loaded.
        #expect(QwenImage21SnapshotLayout.builtEntries.first == "quantization.json")
        #expect(
            QwenImage21SnapshotLayout.directories
                == ["transformer", "text_encoder", "vae", "scheduler", "processor"])
        // A packed variant carries no `model_index.json`; the release does, and it is what
        // tells 2.1 from Qwen-Image 2512 before a weight is read.
        #expect(!QwenImage21SnapshotLayout.builtEntries.contains("model_index.json"))
        #expect(QwenImage21SnapshotLayout.releaseEntries.contains("model_index.json"))
        #expect(QwenImage21SnapshotLayout.releaseEntries.count == 17)
        #expect(
            QwenImage21SnapshotLayout.releaseEntries.contains(
                "text_encoder/model-00004-of-00004.safetensors"))
    }
}
