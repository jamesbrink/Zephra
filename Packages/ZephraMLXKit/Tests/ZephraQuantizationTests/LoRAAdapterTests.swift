import Foundation
import MLX
import Testing
import ZephraTestSupport

@testable import ZephraQuantization

/// Merging a low-rank adapter into the weights it modifies. The tensors here are a few dozen
/// values, so nothing loads a real adapter.
@Suite("LoRA adapter")
struct LoRAAdapterTests {
    @Test("the update is the scaled product of the two factors, added to the weight")
    func mergesTheScaledProduct() throws {
        let scratch = Scratch("LoRAAdapter")
        // A rank-2 update whose product is easy to read: down is 1s, up is 2s, so every entry of
        // the product is 2 + 2 = 4, and alpha 1 over rank 2 halves it to 2.
        try Self.write(
            [
                "blocks.0.to_q.lora_down.weight": MLXArray.ones([2, 3]),
                "blocks.0.to_q.lora_up.weight": MLXArray.full([4, 2], values: MLXArray(2.0)),
                "blocks.0.to_q.alpha": MLXArray(1.0),
            ],
            to: scratch.url("adapter.safetensors")
        )

        let adapter = try LoRAAdapter(contentsOf: [scratch.url("adapter.safetensors")])
        let merged = try adapter.applied(
            to: MLXArray.zeros([4, 3]), named: "blocks.0.to_q.weight")
        MLX.eval(merged)
        #expect(merged.shape == [4, 3])
        #expect(merged.asType(.float32).asArray(Float.self).allSatisfy { $0 == 2 })
    }

    @Test("a weight the adapter says nothing about comes through untouched")
    func leavesUnadaptedWeightsAlone() throws {
        let scratch = Scratch("LoRAAdapter")
        try Self.write(Self.pair(), to: scratch.url("adapter.safetensors"))
        let adapter = try LoRAAdapter(contentsOf: [scratch.url("adapter.safetensors")])

        let weight = MLXArray.ones([4, 3]).asType(.bfloat16)
        let passed = try adapter.applied(to: weight, named: "blocks.0.to_k.weight")
        #expect(
            passed.dtype == DType.bfloat16,
            "an untouched weight keeps its dtype; only a merged one is promoted to float32"
        )
        #expect(adapter.targetKeys == ["blocks.0.to_q.weight"])
    }

    @Test("every spelling of the two factors reduces to the same weight key")
    func acceptsEverySpellingInCirculation() {
        for name in [
            "blocks.0.to_q.lora_down.weight",
            "blocks.0.to_q.lora_A.weight",
            "blocks.0.to_q.lora_A.default.weight",
            "transformer.blocks.0.to_q.lora_down.weight",
            "diffusion_model.blocks.0.to_q.lora_A.weight",
        ] {
            let parsed = LoRAAdapter.parse(name)
            #expect(parsed?.key == "blocks.0.to_q.weight", "\(name) should name the base weight")
        }
        #expect(LoRAAdapter.parse("blocks.0.to_q.lora_up.weight")?.key == "blocks.0.to_q.weight")
        #expect(
            LoRAAdapter.parse("blocks.0.to_q.weight") == nil,
            "a plain weight read as half an update would merge a checkpoint into itself"
        )
    }

    @Test("half an update is refused rather than merged")
    func refusesAnIncompleteUpdate() throws {
        let scratch = Scratch("LoRAAdapter")
        try Self.write(
            ["blocks.0.to_q.lora_down.weight": MLXArray.ones([2, 3])],
            to: scratch.url("half.safetensors")
        )
        #expect(throws: QuantizationError.incompleteAdapterLayer("blocks.0.to_q.weight")) {
            _ = try LoRAAdapter(contentsOf: [scratch.url("half.safetensors")])
        }
    }

    @Test("an update that is not the shape of its weight is refused")
    func refusesAShapeMismatch() throws {
        let scratch = Scratch("LoRAAdapter")
        try Self.write(Self.pair(), to: scratch.url("adapter.safetensors"))
        let adapter = try LoRAAdapter(contentsOf: [scratch.url("adapter.safetensors")])

        #expect(throws: QuantizationError.self) {
            // The update is 4 by 3; this weight is 4 by 5, which is a different layer entirely.
            _ = try adapter.applied(to: MLXArray.zeros([4, 5]), named: "blocks.0.to_q.weight")
        }
    }

    @Test("an adapter naming weights the component has not got stops the build")
    func unmatchedLayersStopTheBuild() throws {
        let scratch = Scratch("LoRAAdapter")
        try Self.write(
            [
                // A name from a different port of the same model: plausible, and matching
                // nothing, so a silent merge would hand back the base weights.
                "blocks.0.attention.query.lora_down.weight": MLXArray.ones([2, 3]),
                "blocks.0.attention.query.lora_up.weight": MLXArray.ones([4, 2]),
            ],
            to: scratch.url("wrong-names.safetensors")
        )
        try Self.saveWeights(
            ["blocks.0.to_q.weight"], to: scratch.url("source/transformer/model.safetensors"))
        try scratch.write("{}", to: "source/model_index.json")

        #expect(throws: QuantizationError.self) {
            try SnapshotQuantizer.quantize(
                source: scratch.url("source"),
                destination: scratch.url("out"),
                plan: QuantizationPlan(
                    components: [
                        QuantizedComponent(
                            directoryName: "transformer",
                            fallback: try QuantizationPrecision(bits: 4, groupSize: 64),
                            adapters: [scratch.url("wrong-names.safetensors")]
                        )
                    ],
                    verbatimDirectories: []
                )
            )
        }
    }

    @Test("a merged build differs from the same build without the adapter")
    func theMergeReachesThePackedWeights() throws {
        let scratch = Scratch("LoRAAdapter")
        try scratch.write("{}", to: "source/model_index.json")
        try Self.saveWeights(
            ["blocks.0.to_q.weight"], to: scratch.url("source/transformer/model.safetensors"))
        // A rank-2 update over the whole 64 by 128 weight, large enough to survive four-bit
        // packing: without the merge the packed values are the base model's.
        try Self.write(
            [
                "blocks.0.to_q.lora_down.weight": MLXArray.ones([2, 128]).asType(.float32) * 8,
                "blocks.0.to_q.lora_up.weight": MLXArray.ones([64, 2]).asType(.float32) * 8,
            ],
            to: scratch.url("adapter.safetensors")
        )

        let precision = try QuantizationPrecision(bits: 4, groupSize: 64)
        for (output, adapters) in [
            ("base", [URL]()), ("merged", [scratch.url("adapter.safetensors")]),
        ] {
            try SnapshotQuantizer.quantize(
                source: scratch.url("source"),
                destination: scratch.url(output),
                plan: QuantizationPlan(
                    components: [
                        QuantizedComponent(
                            directoryName: "transformer",
                            fallback: precision,
                            adapters: adapters
                        )
                    ],
                    verbatimDirectories: []
                )
            )
        }

        let base = try Self.packedScales(in: scratch.url("base/transformer"))
        let merged = try Self.packedScales(in: scratch.url("merged/transformer"))
        #expect(
            MLX.allClose(base, merged).item(Bool.self) == false,
            "the adapter never reached the tensors that were packed"
        )
    }

    /// The scales of the one packed layer, which move whenever the weight it came from does.
    private static func packedScales(in directory: URL) throws -> MLXArray {
        let shard = try #require(
            try FileManager.default
                .contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
                .first { $0.pathExtension == "safetensors" }
        )
        return try #require(try MLX.loadArrays(url: shard)["blocks.0.to_q.scales"])
    }

    /// A complete rank-2 update for `blocks.0.to_q`, shaped 4 by 3.
    private static func pair() -> [String: MLXArray] {
        [
            "blocks.0.to_q.lora_down.weight": MLXArray.ones([2, 3]),
            "blocks.0.to_q.lora_up.weight": MLXArray.ones([4, 2]),
        ]
    }

    private static func write(_ arrays: [String: MLXArray], to url: URL) throws {
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try MLX.save(
            arrays: arrays.mapValues { $0.asType(.float32) }, metadata: [:], url: url)
    }

    /// A source shard holding packable linear weights of 64 by 128.
    private static func saveWeights(_ names: [String], to url: URL) throws {
        try write(
            Dictionary(
                uniqueKeysWithValues: names.map {
                    ($0, MLXArray(0..<(64 * 128), [64, 128]).asType(.float32))
                }),
            to: url
        )
    }
}
