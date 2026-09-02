import Foundation
import MLX
import MLXNN
import Testing

@testable import QwenImage

/// The MMDiT against the reference: one block, then the whole stack.
///
/// A doll's-house width is the right size for this. Every way the port can be wrong is
/// structural — which stream is concatenated first, whether modulation chunks shift before
/// scale, whether the final norm chunks the other way round, which flavour of GELU — and
/// structure is as visible at 32 channels as at 3072.
@Suite("Transformer parity")
struct TransformerParityTests {
    /// Weights under `prefix`, with the prefix removed so they match a module's own keys.
    private static func weights(_ fixture: [String: MLXArray], under prefix: String)
        -> [String: MLXArray]
    {
        var stripped: [String: MLXArray] = [:]
        for (key, value) in fixture where key.hasPrefix(prefix) {
            let name = String(key.dropFirst(prefix.count))
            // Inputs and outputs live beside the weights; they are not parameters.
            guard !name.hasPrefix("in."), !name.hasPrefix("out.") else { continue }
            stripped[name] = value
        }
        return stripped
    }

    private static func frequencies(_ fixture: [String: MLXArray], _ name: String) throws
        -> RotaryFrequencies
    {
        RotaryFrequencies(
            cos: try #require(fixture["block.in.\(name).cos"]),
            sin: try #require(fixture["block.in.\(name).sin"])
        )
    }

    @Test("one dual-stream block matches, both streams out")
    func blockMatchesReference() throws {
        let fixture = try Fixture.load("transformer_block")
        let block = QwenImageTransformerBlock(dim: 32, heads: 2, headDim: 16)
        try block.update(
            parameters: ModuleParameters.unflattened(Self.weights(fixture, under: "block.")),
            verify: .all)
        MLX.eval(block.parameters())

        let (image, text) = block(
            image: try #require(fixture["block.in.image"]),
            text: try #require(fixture["block.in.text"]),
            conditioning: try #require(fixture["block.in.conditioning"]),
            imageFrequencies: try Self.frequencies(fixture, "image_freqs"),
            textFrequencies: try Self.frequencies(fixture, "text_freqs")
        )

        let referenceImage = try #require(fixture["block.out.image"])
        let referenceText = try #require(fixture["block.out.text"])
        #expect(image.shape == referenceImage.shape)
        #expect(text.shape == referenceText.shape)
        // Both are asserted because swapping the two on the way out keeps every shape valid
        // when the streams happen to be the same width.
        let imageDifference = Fixture.maxAbsoluteDifference(image, referenceImage)
        let textDifference = Fixture.maxAbsoluteDifference(text, referenceText)
        #expect(imageDifference < 1e-4, "image stream differs by \(imageDifference)")
        #expect(textDifference < 1e-4, "text stream differs by \(textDifference)")
    }

    @Test("the whole stack matches, top and tail included")
    func modelMatchesReference() throws {
        let fixture = try Fixture.load("transformer_model")
        let configuration = QwenImageTransformerConfiguration(
            attentionHeadDim: 16,
            axesDimsRope: [4, 6, 6],
            guidanceEmbeds: false,
            inChannels: 8,
            jointAttentionDim: 24,
            numAttentionHeads: 2,
            numLayers: 2,
            outChannels: 2,
            patchSize: 2
        )
        let transformer = QwenImageTransformer(try configuration.validated())
        try transformer.update(
            parameters: ModuleParameters.unflattened(Self.weights(fixture, under: "model.")),
            verify: .all)
        MLX.eval(transformer.parameters())

        let embedding = QwenImageRotaryEmbedding(
            theta: 10000, axesDim: configuration.axesDimsRope)
        let prediction = transformer(
            latents: try #require(fixture["model.in.latents"]),
            text: try #require(fixture["model.in.text"]),
            timestep: try #require(fixture["model.in.timestep"]),
            frequencies: embedding.frequencies(
                frames: 1, height: 3, width: 4, textLength: 5)
        )

        let reference = try #require(fixture["model.out.prediction"])
        #expect(prediction.shape == reference.shape)
        let difference = Fixture.maxAbsoluteDifference(prediction, reference)
        #expect(difference < 1e-4, "prediction differs by \(difference)")
    }

    @Test("every tensor the reference stack carries is one this module has")
    func weightNamesLineUp() throws {
        let fixture = try Fixture.load("transformer_model")
        let configuration = QwenImageTransformerConfiguration(
            attentionHeadDim: 16, axesDimsRope: [4, 6, 6], guidanceEmbeds: false,
            inChannels: 8, jointAttentionDim: 24, numAttentionHeads: 2,
            numLayers: 2, outChannels: 2, patchSize: 2)
        let transformer = QwenImageTransformer(configuration)
        let ours = Set(transformer.parameters().flattened().map(\.0))
        let reference = Set(Self.weights(fixture, under: "model.").keys)
        #expect(reference.subtracting(ours).isEmpty, "unloaded: \(reference.subtracting(ours).sorted())")
        #expect(ours.subtracting(reference).isEmpty, "unfilled: \(ours.subtracting(reference).sorted())")
    }
}
