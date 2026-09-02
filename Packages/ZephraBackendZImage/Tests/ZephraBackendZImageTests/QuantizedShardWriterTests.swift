import Foundation
import MLX
import Testing
import ZephraTestSupport

@testable import ZephraBackendZImage

/// The spill-and-rename contract: a shard per budget's worth of tensors, safetensors names that
/// carry the total, and a map from tensor name to the shard it landed in.
@Suite("Quantized shard writer")
struct QuantizedShardWriterTests {
    /// One tensor of 64 float32 values, which is 256 bytes by the writer's own accounting.
    private static let tensorBytes = 256

    @Test("tensors spill to a new shard once the budget is reached")
    func spillsAtTheBudget() throws {
        let scratch = Scratch("QuantizedShardWriter")
        let directory = try scratch.make("transformer", isDirectory: true)
        let writer = QuantizedShardWriter(
            directory: directory, budgetBytes: Self.tensorBytes + 1)

        for name in ["a", "b", "c"] { try writer.add(name, Self.tensor()) }
        let shardOfTensor = try writer.finish(relativeTo: "transformer")

        #expect(Self.shardNames(in: directory) == [
            "model-00001-of-00003.safetensors",
            "model-00002-of-00003.safetensors",
            "model-00003-of-00003.safetensors",
        ])
        #expect(shardOfTensor["a"] == "transformer/model-00001-of-00003.safetensors")
        #expect(shardOfTensor["b"] == "transformer/model-00002-of-00003.safetensors")
        #expect(shardOfTensor["c"] == "transformer/model-00003-of-00003.safetensors")
    }

    @Test("the shard total is only fixed up at finish, so a lone shard loses the suffix")
    func totalIsDecidedAtTheEnd() throws {
        let scratch = Scratch("QuantizedShardWriter")
        let directory = try scratch.make("text_encoder", isDirectory: true)
        let writer = QuantizedShardWriter(directory: directory, budgetBytes: 1 << 20)

        try writer.add("only", Self.tensor())
        // Nothing bears its final name until the count is known, so mid-run there is only
        // staging on disk.
        #expect(Self.shardNames(in: directory).isEmpty)

        let shardOfTensor = try writer.finish(relativeTo: "text_encoder")
        #expect(Self.shardNames(in: directory) == ["model.safetensors"])
        #expect(shardOfTensor == ["only": "text_encoder/model.safetensors"])
    }

    @Test("two tensors that fit together share a shard, and both are readable from it")
    func tensorsWithinBudgetShareAShard() throws {
        let scratch = Scratch("QuantizedShardWriter")
        let directory = try scratch.make("transformer", isDirectory: true)
        let writer = QuantizedShardWriter(
            directory: directory, budgetBytes: Self.tensorBytes * 2)

        try writer.add("first", Self.tensor())
        try writer.add("second", Self.tensor())
        try writer.add("third", Self.tensor())
        let shardOfTensor = try writer.finish(relativeTo: "transformer")

        #expect(shardOfTensor["first"] == shardOfTensor["second"])
        #expect(shardOfTensor["third"] != shardOfTensor["first"])
        #expect(Self.shardNames(in: directory).count == 2)

        let written = try MLX.loadArrays(
            url: directory.appending(path: "model-00001-of-00002.safetensors"))
        #expect(Set(written.keys) == ["first", "second"])
    }

    @Test("every tensor added ends up in the returned map")
    func everyTensorIsAccountedFor() throws {
        let scratch = Scratch("QuantizedShardWriter")
        let directory = try scratch.make("transformer", isDirectory: true)
        let writer = QuantizedShardWriter(
            directory: directory, budgetBytes: Self.tensorBytes + 1)

        let names = (0..<7).map { "layers.\($0).attention.to_q.weight" }
        for name in names { try writer.add(name, Self.tensor()) }
        let shardOfTensor = try writer.finish(relativeTo: "transformer")

        #expect(Set(shardOfTensor.keys) == Set(names))
        #expect(
            shardOfTensor.values.allSatisfy { path in
                Self.shardNames(in: directory).contains(path.replacingOccurrences(
                    of: "transformer/", with: ""))
            },
            "a path in the manifest that names no shard on disk is a broken snapshot"
        )
    }

    private static func tensor() -> MLXArray {
        MLXArray(0..<64, [64]).asType(.float32)
    }

    /// The shards on disk, in name order. Staging names are not shards yet.
    private static func shardNames(in directory: URL) -> [String] {
        let contents =
            (try? FileManager.default.contentsOfDirectory(
                at: directory, includingPropertiesForKeys: nil)) ?? []
        return contents.map(\.lastPathComponent).filter { $0.hasPrefix("model") }.sorted()
    }
}
