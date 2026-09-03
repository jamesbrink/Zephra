import Foundation
import MLX
import Testing
import ZephraQuantization
import ZephraTestSupport
import ZImage

@testable import ZephraBackendZImage

/// What `quantization.json` says, read back through the vendored type the loader decodes it
/// with. The snapshots here are a few tensors of 64 by 128, so nothing loads real weights.
@Suite("Quantization manifest")
struct QuantizationManifestTests {
    @Test("a uniform plan states one precision in the header and on every layer")
    func uniformPlanDescribesTheWholeBuild() throws {
        let scratch = Scratch("QuantizationManifest")
        try Self.makeSource(in: scratch, transformerLayers: 2, textEncoderLayers: 1)
        let precision = try QuantizationPrecision(bits: 8, groupSize: 64)

        let manifest = try Self.quantize(
            in: scratch,
            plan: ZImageQuantizationPlan.plan(transformer: precision, textEncoder: precision)
        )
        #expect(manifest.bits == 8)
        #expect(manifest.groupSize == 64)
        #expect(manifest.modelId == "acme/weights")
        #expect(manifest.layers.count == 3)
        #expect(manifest.layers.allSatisfy { $0.bits == 8 && $0.groupSize == 64 })
    }

    @Test("a mixed plan puts each precision on its own layers and falls back to the commonest")
    func mixedPlanDescribesItselfLayerByLayer() throws {
        let scratch = Scratch("QuantizationManifest")
        // One four-bit transformer layer against two eight-bit text encoder layers, so the
        // fallback the header states cannot have been copied from the transformer.
        try Self.makeSource(in: scratch, transformerLayers: 1, textEncoderLayers: 2)

        let manifest = try Self.quantize(
            in: scratch,
            plan: ZImageQuantizationPlan.plan(
                transformer: try QuantizationPrecision(bits: 4, groupSize: 64),
                textEncoder: try QuantizationPrecision(bits: 8, groupSize: 32)
            )
        )
        #expect(
            manifest.layers.allSatisfy { $0.bits != nil && $0.groupSize != nil },
            "a layer with no precision of its own would silently take the header's"
        )
        let transformer = try #require(
            manifest.layers.first { $0.name == "layers.0.attention.to_q" })
        #expect(transformer.bits == 4)
        #expect(transformer.groupSize == 64)
        let encoder = try #require(
            manifest.layers.first { $0.name == "model.layers.0.mlp.down_proj" })
        #expect(encoder.bits == 8)
        #expect(encoder.groupSize == 32)

        #expect(
            manifest.bits == 8 && manifest.groupSize == 32,
            "the header is the fallback for a name the loader misses, not the transformer's half"
        )
    }

    @Test("the fallback is the precision the most layers were packed at")
    func commonestPrecisionAcrossLayers() throws {
        let four = try QuantizationPrecision(bits: 4, groupSize: 64)
        let eight = try QuantizationPrecision(bits: 8, groupSize: 64)
        let layers = [Self.layer(four), Self.layer(eight), Self.layer(eight)]

        #expect(QuantizationManifest.commonestPrecision(across: layers) == eight)
        #expect(QuantizationManifest.commonestPrecision(across: []) == nil)
        #expect(
            QuantizationManifest.commonestPrecision(across: [Self.layer(four), Self.layer(eight)])
                == four,
            "a tie goes to the first, which is the transformer's, because it is written first"
        )
    }

    /// Runs the quantizer over the scratch snapshot and reads the manifest back.
    private static func quantize(
        in scratch: Scratch, plan: QuantizationPlan
    ) throws -> ZImageQuantizationManifest {
        try SnapshotQuantizer.quantize(
            source: scratch.url("source"),
            destination: scratch.url("out"),
            plan: plan,
            sourceName: "acme/weights",
            shardBudgetBytes: 1 << 20
        )
        return try ZImageQuantizationManifest.load(
            from: scratch.url("out/quantization.json"))
    }

    /// A source snapshot holding one shard per component, each a few packable linear weights.
    private static func makeSource(
        in scratch: Scratch, transformerLayers: Int, textEncoderLayers: Int
    ) throws {
        try scratch.write("{}", to: "source/model_index.json")
        try save(
            (0..<transformerLayers).map { "layers.\($0).attention.to_q.weight" },
            to: scratch.url("source/transformer/model.safetensors")
        )
        try save(
            (0..<textEncoderLayers).map { "model.layers.\($0).mlp.down_proj.weight" },
            to: scratch.url("source/text_encoder/model.safetensors")
        )
    }

    private static func save(_ names: [String], to url: URL) throws {
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let weight = MLXArray(0..<(64 * 128), [64, 128]).asType(.float32)
        try MLX.save(
            arrays: Dictionary(uniqueKeysWithValues: names.map { ($0, weight) }),
            metadata: [:],
            url: url
        )
    }

    private static func layer(_ precision: QuantizationPrecision) -> QuantizationManifest.Layer {
        QuantizationManifest.Layer(
            name: "layers.0.attention.to_q",
            shape: [64, 128],
            inDim: 128,
            outDim: 64,
            file: "transformer/model.safetensors",
            precision: precision,
            mode: "affine"
        )
    }
}
