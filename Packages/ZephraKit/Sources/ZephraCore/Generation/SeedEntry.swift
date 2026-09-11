import Foundation

/// Reading a seed a person typed or pasted.
///
/// Two spellings are accepted, because two are shown: the whole seed as the decimal number the
/// tooltip and every file name carry, and the short hex label the control draws (`7A3F·9C2E`),
/// which names the seed's leading eight hex digits. A label is only the top half of the value,
/// so it comes back as that half over zeros — the same seed the label would draw, not the same
/// seed it was read off, which no eight characters could recover.
///
/// Hex is what a hex letter, a `0x` prefix or the label's middle dot say it is; digits alone
/// are decimal, since that is what the tooltip shows and what a pasted number means. Sixteen
/// hex digits are the whole value, eight are the label, and any other count is refused rather
/// than guessed at.
public enum SeedEntry {
    /// The seed `text` names, or nil when it names none.
    public static func parse(_ text: String) -> UInt64? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let lower = trimmed.lowercased()
        let prefixed = lower.hasPrefix("0x")
        let body = String(prefixed ? lower.dropFirst(2) : lower[...])
        let digits = body.filter { $0 != "·" && $0 != " " }
        let isHex = prefixed || body.contains("·") || digits.contains { "abcdef".contains($0) }
        guard !isHex else { return parseHex(digits) }
        guard digits.allSatisfy(\.isNumber), digits.count == body.count else { return nil }
        return UInt64(digits)
    }

    private static func parseHex(_ digits: String) -> UInt64? {
        guard digits.allSatisfy(\.isHexDigit) else { return nil }
        switch digits.count {
        case 8: return UInt64(digits, radix: 16).map { $0 << 32 }
        case 16: return UInt64(digits, radix: 16)
        default: return nil
        }
    }
}
