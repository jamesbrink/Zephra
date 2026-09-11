/// How a 64-bit seed is shown on screen: eight hex characters in two groups, enough to recognise
/// a seed at a glance without a twenty-digit number crowding the row.
///
/// It lives here rather than in either app because the library searches by it — what a person
/// can read off the inspector is what they will paste into the search box, so the same label
/// has to be in the search key that the interface draws — and because the phone draws the same
/// label from the same function rather than from a copy of it.
extension UInt64 {
    /// The seed's leading eight hex digits, upper case, split in the middle: `7A3F·9C2E`.
    public var shortSeedLabel: String {
        let hex = String(self, radix: 16, uppercase: true)
        let padded = String(repeating: "0", count: Swift.max(0, 16 - hex.count)) + hex
        let head = padded.prefix(8)
        return "\(head.prefix(4))·\(head.suffix(4))"
    }
}
