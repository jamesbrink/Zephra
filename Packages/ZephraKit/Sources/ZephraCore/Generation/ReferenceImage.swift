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
/// - `1` is the ordinary text-to-image path — the loop starts at the first sigma, which is
///   pure noise, and the reference contributes nothing.
/// - `0` would return the reference unchanged, which is why no model offers it.
/// - `0.6`, the default, keeps the reference's composition and colour while re-drawing the
///   detail from the prompt.
///
/// Concretely, the loop starts at the first step whose sigma is at or below `strength`, and the
/// latent it starts from is the encoded reference mixed with that step's share of noise. So a
/// nine-step run at `0.6` runs the last four or five of its steps, and the step count the user
/// asked for stays the count they see: progress still reports out of nine.
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

    /// The SHA-256 of any file's bytes, lowercase hex, read without mapping the whole file into
    /// memory eagerly.
    public static func digest(ofFileAt url: URL) throws -> String {
        let data = try Data(contentsOf: url, options: .mappedIfSafe)
        return SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
}
