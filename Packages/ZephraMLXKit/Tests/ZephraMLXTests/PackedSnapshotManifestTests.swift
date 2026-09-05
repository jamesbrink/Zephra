import Foundation
import MLX
import MLXNN
import Testing
import ZephraMLX
import ZephraTestSupport

/// The manifest is what says a snapshot is packed, so a broken one must be a refusal that
/// names the file, never a snapshot quietly taken for full precision.
@Suite("The packed snapshot manifest every family reads")
struct PackedSnapshotManifestTests {
    /// The smallest module tree with a layer the packer could have packed.
    private final class Probe: Module {
        @ModuleInfo var linear = Linear(64, 32)
    }

    @Test("a missing manifest reads as nil")
    func missingManifestIsNil() throws {
        let scratch = Scratch("PackedManifest")
        try scratch.make("snapshot", isDirectory: true)
        #expect(try PackedSnapshotManifest.read(from: scratch.url("snapshot")) == nil)
    }

    @Test("a manifest that is not JSON is refused with its path")
    func malformedManifestIsRefused() throws {
        let scratch = Scratch("PackedManifest")
        let url = try scratch.write("{ not json", to: "snapshot/quantization.json")
        let thrown = #expect(throws: PackedSnapshotError.self) {
            _ = try PackedSnapshotManifest.read(from: scratch.url("snapshot"))
        }
        guard case .malformedManifest(let named, let reason)? = thrown else {
            Issue.record("expected malformedManifest, got \(String(describing: thrown))")
            return
        }
        #expect(named == url)
        #expect(!reason.isEmpty)
    }

    @Test("a well-formed manifest reads, per-layer precision and all")
    func wellFormedManifestReads() throws {
        let scratch = Scratch("PackedManifest")
        try scratch.write(
            #"{"bits":4,"group_size":64,"layers":[{"name":"a","bits":8,"group_size":32}]}"#,
            to: "snapshot/quantization.json")
        let manifest = try #require(
            try PackedSnapshotManifest.read(from: scratch.url("snapshot")))
        #expect(manifest.precision(of: "a") == (8, 32))
        #expect(manifest.precision(of: "b") == (4, 64))
    }

    @Test("packed shards with no manifest are refused before the tree is reshaped")
    func packedShardsWithoutManifestAreRefused() throws {
        let probe = Probe()
        let weights: [String: MLXArray] = [
            "linear.weight": MLXArray.zeros([32, 8], dtype: .uint32),
            "linear.scales": MLXArray.ones([32, 1]),
            "linear.biases": MLXArray.zeros([32, 1]),
        ]
        #expect(throws: PackedSnapshotError.packedWithoutManifest(firstKey: "linear.scales")) {
            try PackedWeightLoading.load(into: probe, weights: weights, manifest: nil)
        }
        #expect(
            probe.linear is QuantizedLinear == false,
            "the refusal comes before any layer is turned into a packed one"
        )
    }

    @Test("a packed layer is looked up under the checkpoint's name, and lands as a packed one")
    func packedLayerIsRenamedForTheManifest() throws {
        let scratch = Scratch("PackedManifest")
        try scratch.write(
            #"{"bits":4,"group_size":64,"layers":[{"name":"ckpt.linear","bits":8,"group_size":32}]}"#,
            to: "snapshot/quantization.json")
        let manifest = try #require(
            try PackedSnapshotManifest.read(from: scratch.url("snapshot")))
        let probe = Probe()
        let (packed, scales, biases) = MLX.quantized(
            MLXRandom.normal([32, 64], key: MLXRandom.key(4)), groupSize: 32, bits: 8)
        let bias = try #require(biases, "affine packing carries a bias per group")
        try PackedWeightLoading.load(
            into: probe,
            weights: [
                "linear.weight": packed, "linear.scales": scales, "linear.biases": bias,
                "linear.bias": MLXArray.zeros([32]),
            ],
            manifest: manifest,
            checkpointName: { "ckpt." + $0 })
        let quantized = try #require(probe.linear as? QuantizedLinear)
        #expect(quantized.bits == 8 && quantized.groupSize == 32)
    }
}
