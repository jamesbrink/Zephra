import Foundation
import ZephraCore
import ZephraSnapshot

/// Where LTX-2.5's packed variant is, if it is one this build can load.
///
/// `LocalSnapshot.packedVariant` answers by directory listing and provenance stamp, which is
/// the right test for every family but not quite enough here: the plan now packs the video
/// autoencoder's encoder into the `vae` component beside its decoder, and a variant built
/// before it did has the same directories and, for a build made between the catalog naming the
/// encoder file and the plan reading it, the same stamp. Such a variant loads its decoder and
/// then fails on the encoder, for text-to-video too. So the `vae` shard's header is read as
/// well — a few kilobytes at the front of the file — and a variant whose header carries no
/// `vae_encoder.` tensor is not a variant, and is built again.
enum LTX2PackedVariant {
    /// The tensor prefix the encoder's weights carry in the pack and in the packed variant.
    static let encoderPrefix = "vae_encoder."

    /// The packed variant to load, or nil when the one on disk is missing, stale, or built
    /// without the encoder.
    static func find(of descriptor: ModelDescriptor, in locations: ModelLocations) -> URL? {
        guard let packed = LocalSnapshot.ltx2.packedVariant(of: descriptor, in: locations),
            holdsEncoder(packed)
        else { return nil }
        return packed
    }

    /// Whether some shard under `variant/vae` names an encoder tensor in its header.
    static func holdsEncoder(_ variant: URL) -> Bool {
        let vae = variant.appending(path: "vae")
        guard let shards = try? FileManager.default.contentsOfDirectory(
            at: vae, includingPropertiesForKeys: nil)
        else { return false }
        return shards
            .filter { $0.pathExtension == "safetensors" }
            .contains { shard in tensorNames(in: shard).contains { $0.hasPrefix(encoderPrefix) } }
    }

    /// The tensor names a safetensors file's header lists: eight little-endian bytes of header
    /// length, then that much JSON whose keys are the names (and `__metadata__`).
    static func tensorNames(in shard: URL) -> [String] {
        guard let handle = try? FileHandle(forReadingFrom: shard) else { return [] }
        defer { try? handle.close() }
        guard let prefix = try? handle.read(upToCount: 8), prefix.count == 8 else { return [] }
        let length = prefix.withUnsafeBytes { $0.loadUnaligned(as: UInt64.self).littleEndian }
        guard length > 0, length < 64 * 1024 * 1024,
            let header = try? handle.read(upToCount: Int(length)),
            let json = try? JSONSerialization.jsonObject(with: header) as? [String: Any]
        else { return [] }
        return json.keys.filter { $0 != "__metadata__" }
    }
}
