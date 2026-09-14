import Foundation
import MLX
import Testing
import ZephraMLX
import ZephraTestSupport

@testable import Flux2

/// The two block stacks read from a shard on every pass rather than held.
///
/// Both models are cast to bfloat16 before anything else, because the cast is the whole of what
/// this pins. The fixture's tensors are float32, as a packer's scales are on disk; the cast
/// makes the stream's slots bfloat16, so every pass has to hand its layers `asType(.bfloat16)`
/// over the raw float32 node. Without the cast the slots would capture float32, the re-cast
/// would be a no-op, and the suite would pass while saying nothing about the one thing that
/// widened klein's stream once already. The streamed model is never evaluated before its
/// streams are attached, so pass one reads the shard rather than resident memory.
///
/// The reference is not compared against here: bfloat16 weights move the velocity far past the
/// 1e-4 the dumped tensors are pinned at, and `TransformerParityTests.wholeModel` already makes
/// that claim in float32. What is claimed here is that streaming changes nothing.
@Suite("The transformer's stacks stream from disk to the resident answer")
struct TransformerStreamingTests {
    /// The blocks' tensors under the checkpoint's own names, as one shard a stream can read.
    private static func shard(_ fixture: [String: MLXArray], in scratch: Scratch) throws -> URL {
        let weights = Fixture.weights(fixture, under: "model.").filter {
            $0.key.hasPrefix(Flux2ResidentParameters.doubleBlocks + ".")
                || $0.key.hasPrefix(Flux2ResidentParameters.singleBlocks + ".")
        }
        let url = try scratch.make("shards/model.safetensors")
        try MLX.save(arrays: weights, url: url)
        return url
    }

    /// A model holding the fixture's weights cast to bfloat16, evaluated only when asked: a
    /// model about to be streamed must not be, or its first pass reads memory rather than disk.
    private static func loaded(_ fixture: [String: MLXArray], evaluating: Bool) throws
        -> Flux2Transformer
    {
        let model = Flux2Transformer(try TransformerParityTests.configuration())
        try PackedWeightLoading.load(
            into: model,
            weights: Flux2TransformerWeights.sanitized(Fixture.weights(fixture, under: "model.")),
            manifest: nil)
        PackedWeightLoading.castFloatParameters(of: model, to: .bfloat16)
        if evaluating { MLX.eval(model.parameters()) }
        return model
    }

    private static func predict(_ model: Flux2Transformer, _ fixture: [String: MLXArray]) throws
        -> MLXArray
    {
        let text = try #require(fixture["model.in.text"])
        return try model(
            latents: try #require(fixture["model.in.latents"]),
            text: text,
            timestep: try #require(fixture["model.in.timestep"]),
            frequencies: try TransformerParityTests.frequencies(fixture, under: "model."),
            textLength: text.shape[1])
    }

    @Test("two streamed passes give the resident velocity, bfloat16 slots and all")
    func streamedMatchesResident() throws {
        let fixture = try Fixture.load("transformer_model")
        let scratch = Scratch()
        defer { withExtendedLifetime(scratch) {} }  // the shards are read lazily, at eval, not at load
        let index = try ShardIndex(shards: [try Self.shard(fixture, in: scratch)])

        let resident = try Self.predict(try Self.loaded(fixture, evaluating: true), fixture)
        let model = try Self.loaded(fixture, evaluating: false)
        model.doubleStream = try LayerWeightStream(
            layers: model.doubleBlocks, keyPrefix: Flux2ResidentParameters.doubleBlocks,
            index: index, depth: 1,
            checkpointName: Flux2TransformerWeights.checkpointName(of:))
        model.singleStream = try LayerWeightStream(
            layers: model.singleBlocks, keyPrefix: Flux2ResidentParameters.singleBlocks,
            index: index, depth: 1)

        // Twice, so the second pass runs on the nodes the first handed back.
        for _ in 0..<2 {
            let streamed = try Self.predict(model, fixture)
            #expect(Fixture.maxAbsoluteDifference(streamed, resident) < 1e-6)
        }
        // Each stack read its own weights, and read all of them: the two are different types,
        // so they are asked one at a time rather than through a heterogeneous array.
        try Self.expectAPassWasRead(
            lastPassBytes: try #require(model.doubleStream).lastPass?.bytes,
            bytesPerPass: try #require(model.doubleStream).bytesPerPass)
        try Self.expectAPassWasRead(
            lastPassBytes: try #require(model.singleStream).lastPass?.bytes,
            bytesPerPass: try #require(model.singleStream).bytesPerPass)
    }

    /// A stream that ran a pass, and read the whole stack doing it. Both halves matter: the
    /// equality alone holds when a stream never ran and both sides are nothing.
    private static func expectAPassWasRead(lastPassBytes: Int?, bytesPerPass: Int) throws {
        #expect(bytesPerPass > 0)
        #expect(try #require(lastPassBytes) == bytesPerPass)
    }

    @Test("a stack whose tensors the shards do not carry is refused at load")
    func missingTensorIsRefusedAtLoad() throws {
        let fixture = try Fixture.load("transformer_model")
        let scratch = Scratch()
        defer { withExtendedLifetime(scratch) {} }  // the shards are read lazily, at eval, not at load
        // The single-stream blocks alone, so the dual-stream stack has nothing to read.
        let weights = Fixture.weights(fixture, under: "model.").filter {
            $0.key.hasPrefix(Flux2ResidentParameters.singleBlocks + ".")
        }
        let url = try scratch.make("shards/model.safetensors")
        try MLX.save(arrays: weights, url: url)
        let model = try Self.loaded(fixture, evaluating: false)

        #expect(throws: LayerWeightStreamError.self) {
            _ = try LayerWeightStream(
                layers: model.doubleBlocks, keyPrefix: Flux2ResidentParameters.doubleBlocks,
                index: try ShardIndex(shards: [url]), depth: 1,
                checkpointName: Flux2TransformerWeights.checkpointName(of:))
        }
    }
}
