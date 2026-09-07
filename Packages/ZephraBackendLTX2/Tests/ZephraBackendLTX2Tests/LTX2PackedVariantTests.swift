import Foundation
import Testing
import ZephraTestSupport

@testable import ZephraBackendLTX2

@Suite("a packed variant counts only when its vae shard carries the encoder")
struct LTX2PackedVariantTests {
    /// A safetensors file holding nothing but a header naming `tensors`.
    private func writeShard(named tensors: [String], to url: URL) throws {
        var header: [String: Any] = ["__metadata__": ["format": "pt"]]
        for name in tensors {
            header[name] = ["dtype": "BF16", "shape": [1], "data_offsets": [0, 2]]
        }
        let json = try JSONSerialization.data(withJSONObject: header)
        var bytes = Data()
        var length = UInt64(json.count).littleEndian
        bytes.append(Data(bytes: &length, count: 8))
        bytes.append(json)
        bytes.append(Data(repeating: 0, count: 2 * tensors.count))
        try bytes.write(to: url)
    }

    @Test("a shard header is read for its tensor names, and the metadata key is not one")
    func headerNamesAreRead() throws {
        let scratch = Scratch()
        try FileManager.default.createDirectory(at: scratch.root, withIntermediateDirectories: true)
        let shard = scratch.root.appending(path: "model.safetensors")
        try writeShard(named: ["vae_decoder.conv_in.conv.weight", "vae_encoder.conv_in.conv.weight"], to: shard)
        let names = LTX2PackedVariant.tensorNames(in: shard)
        #expect(names.sorted() == ["vae_decoder.conv_in.conv.weight", "vae_encoder.conv_in.conv.weight"])
    }

    @Test("a variant packed before the encoder joined the plan does not hold one")
    func decoderOnlyVariantIsRejected() throws {
        let scratch = Scratch()
        let vae = scratch.root.appending(path: "vae")
        try FileManager.default.createDirectory(at: vae, withIntermediateDirectories: true)
        try writeShard(named: ["vae_decoder.conv_in.conv.weight"], to: vae.appending(path: "model.safetensors"))
        #expect(!LTX2PackedVariant.holdsEncoder(scratch.root))
    }

    @Test("a variant whose vae shard names an encoder tensor holds one, whichever shard it is in")
    func encoderInAnyShardCounts() throws {
        let scratch = Scratch()
        let vae = scratch.root.appending(path: "vae")
        try FileManager.default.createDirectory(at: vae, withIntermediateDirectories: true)
        try writeShard(named: ["vae_decoder.conv_in.conv.weight"], to: vae.appending(path: "model-00001-of-00002.safetensors"))
        try writeShard(named: ["vae_encoder.conv_in.conv.weight"], to: vae.appending(path: "model-00002-of-00002.safetensors"))
        #expect(LTX2PackedVariant.holdsEncoder(scratch.root))
    }

    @Test("a variant with no vae directory, or an unreadable shard, holds no encoder")
    func missingOrUnreadableIsNotAnEncoder() throws {
        let scratch = Scratch()
        #expect(!LTX2PackedVariant.holdsEncoder(scratch.root))
        let vae = scratch.root.appending(path: "vae")
        try FileManager.default.createDirectory(at: vae, withIntermediateDirectories: true)
        try Data([1, 2, 3]).write(to: vae.appending(path: "model.safetensors"))
        #expect(!LTX2PackedVariant.holdsEncoder(scratch.root))
    }
}
