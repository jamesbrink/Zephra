/// How a seed is written wherever the interface shows one: the capsule's chip, the inspectors'
/// Seed row, the running run's column and the popover a seed is typed into.
///
/// Two spellings of one `UInt64`. The short hex label is the default, because a twenty-digit
/// number crowds every row it is put in and eight hex characters are enough to tell two seeds
/// apart at a glance; the decimal is for the person who copies seeds between tools, where the
/// number is what the other side wants. Nothing on disk changes with the choice: the record,
/// the file name and the search key carry the number, and the search key carries the label
/// too, so a seed read off the screen under either setting is found by the search box.
///
/// It lives in the engine beside `shortSeedLabel` because `ImageFacts` formats the Seed row
/// here, off the view; the raw value is a preference key in the app.
public enum SeedFormat: String, CaseIterable, Sendable, Codable {
    /// The leading eight hex digits, split in the middle: `7A3F·9C2E`.
    case hex
    /// The whole seed as a decimal number.
    case decimal

    /// How `seed` is shown in a row or on a chip under this setting.
    public func label(_ seed: UInt64) -> String {
        switch self {
        case .hex: seed.shortSeedLabel
        case .decimal: String(seed)
        }
    }

    /// The whole seed, exactly, spelled the way this setting spells seeds: sixteen hex digits
    /// behind `0x`, or the decimal. What the entry field is prefilled with, so what is typed
    /// back reproduces the seed rather than only its label.
    public func exactText(_ seed: UInt64) -> String {
        switch self {
        case .hex:
            let hex = String(seed, radix: 16, uppercase: true)
            return "0x" + String(repeating: "0", count: Swift.max(0, 16 - hex.count)) + hex
        case .decimal:
            return String(seed)
        }
    }
}
