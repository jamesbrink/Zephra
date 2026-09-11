/// How a seed is spelled on the phone: the leading eight hex digits, split in the middle,
/// `7A3F·9C2E`.
///
/// `SeedFormat.hex` on the Mac, which is its default and the only spelling the phone offers —
/// there is no Settings > General here to choose the decimal in. A copy rather than the real
/// thing because `SeedFormat` lives in `ZephraEngine`, which the phone may not link; moving it
/// down into `ZephraCore` beside `SeedEntry`, which the phone does read, is in `ROADMAP.md`.
/// The exact value is what `SeedEntry` reads back, so a seed typed in reproduces a picture.
enum SeedLabel {
    /// The short label a chip shows.
    static func text(_ seed: UInt64) -> String {
        let hex = String(seed, radix: 16, uppercase: true)
        let padded = String(repeating: "0", count: Swift.max(0, 16 - hex.count)) + hex
        let head = padded.prefix(8)
        return "\(head.prefix(4))·\(head.suffix(4))"
    }

    /// The whole seed, as the entry sheet is prefilled with it: sixteen hex digits behind
    /// `0x`, which `SeedEntry.parse` reads back as exactly this seed rather than as its label.
    static func exactText(_ seed: UInt64) -> String {
        let hex = String(seed, radix: 16, uppercase: true)
        return "0x" + String(repeating: "0", count: Swift.max(0, 16 - hex.count)) + hex
    }
}
