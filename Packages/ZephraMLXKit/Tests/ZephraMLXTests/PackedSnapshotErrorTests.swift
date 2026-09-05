import Foundation
import Testing
import ZephraMLX

/// What a person is told when a packed snapshot cannot be loaded: the file, the reason, and
/// the tensor, since each is what fixing it starts from.
@Suite("Packed snapshot errors")
struct PackedSnapshotErrorTests {
    @Test("a malformed manifest names its path and the decoder's reason")
    func malformedManifestNamesThePath() {
        let url = URL(filePath: "/models/qwen-image-2512-4bit/quantization.json")
        let description = PackedSnapshotError.malformedManifest(url, reason: "not JSON")
            .errorDescription ?? ""
        #expect(description.contains("/models/qwen-image-2512-4bit/quantization.json"))
        #expect(description.contains("not JSON"))
        #expect(description.contains("build it again"))
    }

    @Test("packed weights with no manifest name the tensor that gave them away")
    func packedWithoutManifestNamesTheTensor() {
        let description = PackedSnapshotError.packedWithoutManifest(
            firstKey: "blocks.0.attn.to_q.scales"
        ).errorDescription ?? ""
        #expect(description.contains("blocks.0.attn.to_q.scales"))
        #expect(description.contains("quantization.json"))
    }

    @Test("the two cases compare by what they carry")
    func casesAreEquatable() {
        let url = URL(filePath: "/a/quantization.json")
        #expect(
            PackedSnapshotError.malformedManifest(url, reason: "x")
                == PackedSnapshotError.malformedManifest(url, reason: "x"))
        #expect(
            PackedSnapshotError.malformedManifest(url, reason: "x")
                != PackedSnapshotError.packedWithoutManifest(firstKey: "x"))
    }
}
