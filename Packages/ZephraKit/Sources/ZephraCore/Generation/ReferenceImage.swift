import CryptoKit
import Foundation

/// A picture the next generation should start from, and how far it is allowed to travel.
///
/// This is SDEdit: rather than starting the denoising loop from pure noise, the reference is
/// encoded to a latent, noised to the level the schedule expects partway through, and the loop
/// resumes from there. Every family Zephra runs uses the same flow-matching interpolation,
/// `x_t = (1 - sigma) * x0 + sigma * noise`, so one number covers both of them.
///
/// `strength` is that number, read as "how much of the picture to throw away":
///
/// - `1` is the ordinary text-to-image path — the whole run happens, starting from pure noise,
///   and the reference contributes nothing. Models' bounds stop short of it for that reason.
/// - `0` would return the reference unchanged, which is why no model offers it either.
/// - `0.6`, the default, keeps the reference's composition and colour while re-drawing the
///   detail from the prompt.
///
/// Concretely, strength buys a share of the steps: `steps * strength` of them run, rounded and
/// never fewer than one, and the loop enters that far from the end, starting from the encoded
/// reference mixed with that step's share of noise. So a nine-step run at `0.6` runs its last
/// five steps. The step count the user asked for stays the count they see: progress still
/// reports out of nine.
///
/// Reading it as a noise level instead — entering at the first sigma at or below the strength —
/// looks equivalent and is not, because a distilled ladder is not evenly spaced. Qwen-Image's
/// four steps are 1.0, 0.767, 0.456 and 0.02, so every strength from 0.1 to 0.4 would find that
/// 0.02 first and hand the picture back untouched.
public struct ReferenceImage: Hashable, Sendable, Codable {
    /// Where the picture lives. A PNG in the library's `Sources/` folder, in practice, but the
    /// backends decode whatever ImageIO reads.
    public var url: URL
    /// How much of the reference to discard, from 0 (keep it all) to 1 (keep none of it).
    public var strength: Double

    /// Creates a reference to start from.
    public init(url: URL, strength: Double) {
        self.url = url
        self.strength = strength
    }

    /// A copy travelling a different distance from the same picture.
    public func withStrength(_ strength: Double) -> ReferenceImage {
        ReferenceImage(url: url, strength: strength)
    }

    /// The SHA-256 of the file's bytes, lowercase hex.
    ///
    /// A generation record stores this beside the file name, so a record still identifies the
    /// picture it started from after the file is renamed, and can say the picture has changed
    /// when a file with the same name no longer hashes the same.
    ///
    /// Throws whatever reading the file throws; it is the caller's job to decide whether a
    /// missing reference is fatal.
    public func digest() throws -> String {
        try Self.digest(ofFileAt: url)
    }

    /// The SHA-256 of any file's bytes, lowercase hex.
    ///
    /// Read a megabyte at a time rather than in one go: this runs on whatever thread is saving
    /// a generation, and a source image is an arbitrary file the user chose.
    public static func digest(ofFileAt url: URL) throws -> String {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        var hash = SHA256()
        while let chunk = try handle.read(upToCount: 1 << 20), !chunk.isEmpty {
            hash.update(data: chunk)
        }
        return hash.finalize().map { String(format: "%02x", $0) }.joined()
    }
}
