import Foundation
import Logging
import MLX
import Testing
import ZephraMLX
import ZephraTestSupport
import ZImage

/// The vendored kit has no test target by policy, so the streaming suites live beside the
/// backend that turns streaming on. Nothing here loads a real snapshot: a model small enough
/// to build twice in a second exercises the same code the 13 GB one runs.
@Suite("Z-Image's transformer stacks stream to the tensors they would have held")
struct ZImageTransformerStreamingTests {
    /// A model whose three stacks are two blocks each, over a head dimension the rotary table
    /// can fill. `axesDims` must sum to `dim / nHeads`; `axesLens[0]` has to cover the caption
    /// tokens and the image tokens after them.
    static let configuration = """
        {
          "in_channels": 16, "dim": 64, "n_layers": 2, "n_refiner_layers": 2,
          "n_heads": 4, "n_kv_heads": 4, "norm_eps": 1e-5, "qk_norm": true,
          "cap_feat_dim": 32, "rope_theta": 10000.0, "t_scale": 1000.0,
          "axes_dims": [8, 4, 4], "axes_lens": [128, 32, 32]
        }
        """

    /// A model on random weights, evaluated, with those weights saved as a shard under the
    /// names the checkpoint uses — which for these stacks are the module tree's own.
    static func resident(in scratch: Scratch, dropping omitted: String? = nil) throws -> (
        model: ZImageTransformer2DModel, shards: URL
    ) {
        let decoded = try JSONDecoder().decode(
            ZImageTransformerConfig.self, from: Data(configuration.utf8))
        let model = ZImageTransformer2DModel(configuration: decoded)
        var weights = Dictionary(uniqueKeysWithValues: model.parameters().flattened())
        MLX.eval(Array(weights.values))
        if let omitted { weights.removeValue(forKey: omitted) }
        let shard = try scratch.make("shards/model.safetensors")
        try MLX.save(arrays: weights, url: shard)
        model.castFloatParameters(to: .bfloat16)
        MLX.eval(model.parameters())
        return (model, scratch.url("shards"))
    }

    /// A second model filled from the shard through the kit's own weight apply, cast the same
    /// way, with every stack reading from disk.
    static func streamed(from shards: URL, depth: Int) throws -> ZImageTransformer2DModel {
        let decoded = try JSONDecoder().decode(
            ZImageTransformerConfig.self, from: Data(configuration.utf8))
        let model = ZImageTransformer2DModel(configuration: decoded)
        try ZImageWeightsMapping.applyTransformer(
            weights: try MLX.loadArrays(url: shards.appending(path: "model.safetensors")),
            to: model,
            logger: Logger(label: "test"))
        model.castFloatParameters(to: .bfloat16)
        try model.attachStreams(index: try ShardIndex(directory: shards), depth: depth)
        return model
    }

    /// Latents, a timestep and prompt embeddings sized to the tiny configuration.
    static func inputs() -> (latents: MLXArray, timestep: MLXArray, prompt: MLXArray) {
        (MLXArray((0..<(16 * 8 * 8)).map { Float($0) / 1024 }).reshaped(1, 16, 8, 8),
         MLXArray([Float(0.25)], [1]),
         MLXArray((0..<(8 * 32)).map { Float($0) / 256 }).reshaped(1, 8, 32))
    }

    @Test("a streamed step is the resident step, on the first pass and on the second")
    func streamedMatchesResident() throws {
        let scratch = Scratch()
        defer { MLXRuntime.synchronize(); withExtendedLifetime(scratch) {} }  // drain the stream's read-ahead before the folder goes
        let (held, shards) = try Self.resident(in: scratch)
        let reading = try Self.streamed(from: shards, depth: 1)
        let (latents, timestep, prompt) = Self.inputs()

        let expected = try held.forward(latents: latents, timestep: timestep, promptEmbeds: prompt)
        MLX.eval(expected)
        // Twice: the first pass reads the nodes the loader put in, every later one reads the
        // nodes the stream handed back, and the second is where a lost cast would show.
        for _ in 0..<2 {
            let output = try reading.forward(
                latents: latents, timestep: timestep, promptEmbeds: prompt)
            MLX.eval(output)
            #expect(output.shape == expected.shape)
            #expect(MLX.abs(output - expected).max().item(Float.self) == 0)
        }
    }

    @Test("each stack reads its own weights once a pass")
    func everyStackStreams() throws {
        let scratch = Scratch()
        defer { MLXRuntime.synchronize(); withExtendedLifetime(scratch) {} }  // drain the stream's read-ahead before the folder goes
        let (_, shards) = try Self.resident(in: scratch)
        let reading = try Self.streamed(from: shards, depth: 1)
        let (latents, timestep, prompt) = Self.inputs()
        MLX.eval(try reading.forward(latents: latents, timestep: timestep, promptEmbeds: prompt))

        for stream in [reading.layersStream, reading.noiseRefinerStream, reading.contextRefinerStream] {
            let stream = try #require(stream)
            #expect(stream.bytesPerPass > 0)
            #expect(stream.lastPass?.bytes == stream.bytesPerPass)
        }
    }

    @Test("a block tensor the shards have not got is refused at load, not mid-step")
    func missingTensorIsRefusedAtLoad() throws {
        let scratch = Scratch()
        defer { withExtendedLifetime(scratch) {} }  // the shards are read lazily, at eval, not at load
        let (_, shards) = try Self.resident(
            in: scratch, dropping: "layers.1.attention.to_q.weight")
        #expect(throws: LayerWeightStreamError.missingTensor("layers.1.attention.to_q.weight")) {
            try Self.streamed(from: shards, depth: 1)
        }
    }
}
