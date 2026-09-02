/// How a 64-bit seed is shown on screen: eight hex characters in two groups, enough to
/// recognise a seed at a glance without a twenty-digit number crowding the row.
extension UInt64 {
    /// The seed's leading eight hex digits, upper case, split in the middle: `7A3F·9C2E`.
    var shortSeedLabel: String {
        let hex = String(self, radix: 16, uppercase: true)
        let padded = String(repeating: "0", count: Swift.max(0, 16 - hex.count)) + hex
        let head = padded.prefix(8)
        return "\(head.prefix(4))·\(head.suffix(4))"
    }
}
