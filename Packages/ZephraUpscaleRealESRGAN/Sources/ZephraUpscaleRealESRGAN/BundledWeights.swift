import Foundation
import ZephraCore

/// Where the checkpoint lives, which is inside this package rather than on anyone's disk.
///
/// 2.4 MB of float16 travels with the build. That is noise beside a sixteen-gigabyte model
/// download, and carrying it removes an availability state, a download, and a failure mode from
/// the engine; it also means the file Zephra ships is one this repository converted and can
/// regenerate, rather than a third party's mirror of a conversion.
///
/// The conversion itself is `Tools/convert_weights.py`, and `PROVENANCE.md` records the
/// SHA-256 of what it wrote.
public enum BundledWeights {
    /// The file inside the bundle, without its extension.
    public static let name = "realesr-general-x4v3-fp16"

    /// The bundled checkpoint, or nil when this build carries none.
    ///
    /// Nil is a real answer rather than an impossible one: `Bundle.module` resolves differently
    /// inside a generated `.app` than it does under `swift test`, and a missing resource should
    /// grey a button rather than trap.
    public static var url: URL? {
        let located = Bundle.module.url(
            forResource: name, withExtension: "safetensors", subdirectory: "Weights")
        guard let located else { return nil }
        return FileManager.default.fileExists(atPath: located.path(percentEncoded: false))
            ? located : nil
    }

    /// The bundled checkpoint, or the error the engine shows when there is none.
    public static func located() throws -> URL {
        guard let url else {
            throw UpscaleError.weightsMissing(
                "\(name).safetensors is not in this build's resources")
        }
        return url
    }
}
