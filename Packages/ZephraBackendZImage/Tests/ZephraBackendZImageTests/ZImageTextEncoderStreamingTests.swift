import Foundation
import Logging
import MLX
import Testing
import ZephraMLX
import ZephraTestSupport
import ZImage

/// The text encoder is the one stack whose checkpoint name differs from its module path:
/// `model.layers` on disk, `encoder.layers` in the tree. A stream keyed on the wrong one fails
/// at load, so this suite is as much about that as about the arithmetic.
@Suite("Z-Image's text encoder streams to the tensors it would have held")
struct ZImageTextEncoderStreamingTests {
    /// Two layers over a hidden size the attention can split four ways.
    static var configuration: QwenTextEncoderConfiguration {
        QwenTextEncoderConfiguration(
            vocabSize: 64, hiddenSize: 32, numHiddenLayers: 2, numAttentionHeads: 4,
            numKeyValueHeads: 2, intermediateSize: 64, maxPositionEmbeddings: 128, headDim: 8)
    }

    /// An encoder on random weights, evaluated, with those weights saved as a shard under the
    /// checkpoint's own names: the tree's `encoder.` prefix is the file's `model.`.
    static func resident(in scratch: Scratch) throws -> (model: QwenTextEncoder, shards: URL) {
        let model = QwenTextEncoder(configuration: configuration)
        let held = model.parameters().flattened()
        MLX.eval(model.parameters())
        let weights = Dictionary(
            uniqueKeysWithValues: held.map { key, array in
                (key.hasPrefix("encoder.") ? "model." + key.dropFirst("encoder.".count) : key,
                 array)
            })
        try MLX.save(arrays: weights, url: scratch.make("shards/model.safetensors"))
        return (model, scratch.url("shards"))
    }

    /// A second encoder filled from the shard through the kit's own weight apply, with its
    /// layers reading from disk. Nothing is cast: the encoder is not cast at load, so a
    /// streamed encode has to be the resident one exactly.
    static func streamed(from shards: URL, depth: Int) throws -> QwenTextEncoder {
        let model = QwenTextEncoder(configuration: configuration)
        try ZImageWeightsMapping.applyTextEncoder(
            weights: try MLX.loadArrays(url: shards.appending(path: "model.safetensors")),
            to: model,
            logger: Logger(label: "test"))
        try model.attachStream(index: try ShardIndex(directory: shards), depth: depth)
        return model
    }

    /// Twelve token ids, built fresh at each use: an `MLXArray` is not `Sendable`, and a
    /// shared one across tests would be shared mutable state.
    static var tokens: MLXArray {
        MLXArray((0..<12).map { Int32($0 * 3 % 64) }).reshaped(1, 12)
    }

    @Test("a streamed encode is the resident encode, on the first pass and on the second")
    func streamedMatchesResident() throws {
        let scratch = Scratch()
        let (held, shards) = try Self.resident(in: scratch)
        let reading = try Self.streamed(from: shards, depth: 1)

        let (expected, expectedMask) = try held.encode(
            inputIds: Self.tokens, attentionMask: nil)
        // `encodeForZImage` is the door the pipeline actually uses, and the one that asks for
        // every layer's output, so it is what proves the hidden states are still collected
        // inside the streamed step.
        let expectedStates = try held.encodeForZImage(inputIds: Self.tokens, attentionMask: nil)
        MLX.eval(expected, expectedMask)
        MLX.eval(expectedStates)

        for _ in 0..<2 {
            let (output, mask) = try reading.encode(inputIds: Self.tokens, attentionMask: nil)
            MLX.eval(output, mask)
            #expect(output.shape == expected.shape)
            #expect(MLX.abs(output - expected).max().item(Float.self) == 0)
            #expect(MLX.abs(mask - expectedMask).max().item(Int32.self) == 0)

            let states = try reading.encodeForZImage(inputIds: Self.tokens, attentionMask: nil)
            MLX.eval(states)
            #expect(states.count == expectedStates.count)
            for (streamed, resident) in zip(states, expectedStates) {
                #expect(MLX.abs(streamed - resident).max().item(Float.self) == 0)
            }
        }
    }

    @Test("a layer tensor the shards have not got is refused at load, not mid-encode")
    func missingTensorIsRefusedAtLoad() throws {
        let scratch = Scratch()
        let (_, shards) = try Self.resident(in: scratch)
        var weights = try MLX.loadArrays(url: shards.appending(path: "model.safetensors"))
        weights.removeValue(forKey: "model.layers.1.mlp.up_proj.weight")
        try MLX.save(arrays: weights, url: shards.appending(path: "model.safetensors"))
        #expect(throws: LayerWeightStreamError.missingTensor("model.layers.1.mlp.up_proj.weight")) {
            try Self.streamed(from: shards, depth: 1)
        }
    }
}
