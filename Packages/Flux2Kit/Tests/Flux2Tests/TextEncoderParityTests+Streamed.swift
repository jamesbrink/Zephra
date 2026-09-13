import Foundation
import MLX
import MLXNN
import Testing
import ZephraMLX

@testable import Flux2

/// The encoder's layers read from the fixture file on every pass rather than held.
///
/// The tap is what this is really about. Resident, a tap is the enumerated position of a layer
/// in the stack; streamed, the stream hands back the layer and not its index, so the count is
/// kept in the closure. Tapping one layer out is a mistake that produces a plausible picture of
/// the wrong prompt, so every tap is compared against the resident encoder's own, not just the
/// concatenation they end up in.
///
/// Both encoders are cast to bfloat16 first, the fixture's tensors being float32 as a packer's
/// scales are on disk: that is what makes the stream's slots bfloat16 and every release an
/// `asType` over the raw node rather than a no-op. And the streamed encoder is never evaluated
/// before its stream is attached, so its first pass reads the file and not resident memory.
@Suite("The encoder's layers stream from disk without moving the taps")
struct TextEncoderStreamingTests {
    /// The fixture file itself, which is a shard the stream can read: its layer tensors are
    /// already under the checkpoint's `model.layers.N...` names. The two layers past the
    /// deepest tap are in it and simply never asked for.
    private static func index() throws -> ShardIndex {
        let file = try #require(
            Bundle.module.resourceURL?.appending(path: "Fixtures/text_encoder.safetensors"))
        return try ShardIndex(shards: [file])
    }

    /// An encoder whose layers are read from the fixture file, its stream attached after the
    /// cast and before any evaluation.
    private static func streamed(_ fixture: [String: MLXArray], casting: DType?) throws
        -> Qwen3TextEncoder
    {
        let encoder = try TextEncoderParityTests.encoder(
            fixture, casting: casting, evaluating: false)
        encoder.model.stream = try LayerWeightStream(
            layers: encoder.model.layers,
            keyPrefix: Flux2ResidentParameters.textEncoderLayers,
            index: try index(),
            depth: 1)
        return encoder
    }

    @Test("every tap is the resident encoder's, twice over")
    func streamedTapsMatchResident() throws {
        let fixture = try Fixture.load("text_encoder")
        let resident = try TextEncoderParityTests.encoder(
            fixture, casting: .bfloat16, evaluating: true)
        let streamed = try Self.streamed(fixture, casting: .bfloat16)

        let tokens = try #require(fixture["input_ids"])
        let wanted = [0] + TextEncoderParityTests.taps
        let expected = try resident.model.hiddenStates(tokens, validCount: 7, taps: wanted)
        // Twice, so the second pass runs on the nodes the first handed back.
        for _ in 0..<2 {
            let states = try streamed.model.hiddenStates(tokens, validCount: 7, taps: wanted)
            for (tap, pair) in zip(wanted, zip(states, expected)) {
                let difference = Fixture.maxAbsoluteDifference(pair.0, pair.1)
                #expect(difference < 1e-6, Comment(rawValue: "tap \(tap) differs by \(difference)"))
            }
        }
        // Both halves: the equality alone holds when a stream never ran and both sides are nil.
        let stream = try #require(streamed.model.stream)
        #expect(stream.bytesPerPass > 0)
        #expect(try #require(stream.lastPass?.bytes) == stream.bytesPerPass)
    }

    @Test("the conditioning a streamed encoder hands the transformer is the reference's")
    func streamedConditioningMatchesTheReference() throws {
        let fixture = try Fixture.load("text_encoder")
        // Float32 here, since the reference tensors are pinned at 2e-4 and bfloat16 weights
        // move the conditioning well past that. What the cast does to a slot is the test above.
        let encoder = try Self.streamed(fixture, casting: nil)

        let conditioning = try encoder(try #require(fixture["input_ids"]), validCount: 7)

        #expect(conditioning.shape == [1, 12, 192])
        let difference = Fixture.maxAbsoluteDifference(
            conditioning, try #require(fixture["taps_concat"]))
        #expect(difference < 2e-4, Comment(rawValue: "conditioning differs by \(difference)"))
    }
}
