import Foundation
import MLX
import MLXNN
import Testing
import ZephraMLX

@testable import QwenImage

/// The stream's dtype through a packed block.
///
/// The regression test for the audit's finding that this family ran in float32. The packer's
/// scales are float32, MLX's quantized matmul takes its output dtype from them, and one such
/// layer widens every activation after it. The load-time cast is what stops that, and this is
/// the block-sized form of the whole-model question. The parity fixtures above are float32 on
/// purpose and are left that way: the transformer follows its inputs' dtype, so they need no
/// environment to run in.
extension TransformerParityTests {
    /// The fixture's block, packed to four bits the way a snapshot is, scales left as the
    /// packer leaves them.
    private static func packedBlock(_ fixture: [String: MLXArray]) throws
        -> QwenImageTransformerBlock
    {
        let block = QwenImageTransformerBlock(dim: 32, heads: 2, headDim: 16)
        try block.update(
            parameters: ModuleParameters.unflattened(weights(fixture, under: "block.")),
            verify: .all)
        // The doll's house is 32 wide, so the group is 32. The scales come out float32
        // because the source weights are, exactly as the packer's do.
        quantize(model: block, groupSize: 32, bits: 4)
        return block
    }

    @Test("a bfloat16 stream stays bfloat16 through a block")
    func packedBlockKeepsTheStreamDtype() throws {
        let fixture = try Fixture.load("transformer_block")
        let image = try #require(fixture["block.in.image"]).asType(.bfloat16)
        let text = try #require(fixture["block.in.text"]).asType(.bfloat16)
        let conditioning = try #require(fixture["block.in.conditioning"]).asType(.bfloat16)
        let imageFrequencies = try Self.frequencies(fixture, "image_freqs")
        let textFrequencies = try Self.frequencies(fixture, "text_freqs")

        let uncast = try Self.packedBlock(fixture)
        #expect(
            uncast.parameters().flattened().contains {
                $0.0.hasSuffix(".scales") && $0.1.dtype == .float32
            },
            "a packed block carries float32 scales, as a packed snapshot does")
        let (wideImage, wideText) = uncast(
            image: image, text: text, conditioning: conditioning,
            imageFrequencies: imageFrequencies, textFrequencies: textFrequencies)
        #expect(
            wideImage.dtype == .float32 && wideText.dtype == .float32,
            "uncast scales widen the stream, which is the finding")

        let cast = try Self.packedBlock(fixture)
        PackedWeightLoading.castFloatParameters(of: cast, to: .bfloat16)
        let (narrowImage, narrowText) = cast(
            image: image, text: text, conditioning: conditioning,
            imageFrequencies: imageFrequencies, textFrequencies: textFrequencies)
        #expect(narrowImage.dtype == .bfloat16)
        #expect(narrowText.dtype == .bfloat16)
        #expect(
            !cast.parameters().flattened().contains { $0.1.dtype == .float32 },
            "nothing float32 is left in the tree to widen a later block")
    }

    @Test("the whole stack runs in whatever dtype its latents arrive in")
    func modelFollowsItsLatents() throws {
        let fixture = try Fixture.load("transformer_model")
        let configuration = QwenImageTransformerConfiguration(
            attentionHeadDim: 16, axesDimsRope: [4, 6, 6], guidanceEmbeds: false,
            inChannels: 8, jointAttentionDim: 24, numAttentionHeads: 2,
            numLayers: 2, outChannels: 2, patchSize: 2)
        let transformer = QwenImageTransformer(try configuration.validated())
        try transformer.update(
            parameters: ModuleParameters.unflattened(Self.weights(fixture, under: "model.")),
            verify: .all)
        PackedWeightLoading.castFloatParameters(of: transformer, to: .bfloat16)
        let frequencies = QwenImageRotaryEmbedding(
            theta: 10000, axesDim: configuration.axesDimsRope
        ).frequencies(frames: 1, height: 3, width: 4, textLength: 5)

        // The text and the timestep arrive float32, as the encoder and the loop hand them
        // over; only the latents say what the stream is.
        let prediction = try transformer(
            latents: try #require(fixture["model.in.latents"]).asType(.bfloat16),
            text: try #require(fixture["model.in.text"]),
            timestep: try #require(fixture["model.in.timestep"]),
            frequencies: frequencies)
        #expect(prediction.dtype == .bfloat16)
    }
}
