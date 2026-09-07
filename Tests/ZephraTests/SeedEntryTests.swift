import Testing
import ZephraEngine

@testable import Zephra

@Suite("Reading a typed seed")
struct SeedEntryTests {
    @Test("a decimal number is the seed itself")
    func decimal() {
        #expect(SeedEntry.parse("42") == 42)
        #expect(SeedEntry.parse(" 18446744073709551615 ") == UInt64.max)
        #expect(SeedEntry.parse("0") == 0)
    }

    @Test("the short label comes back as the seed's leading half over zeros")
    func shortLabel() {
        let seed: UInt64 = 0x7A3F_9C2E_1234_5678
        #expect(SeedEntry.parse(seed.shortSeedLabel) == 0x7A3F_9C2E_0000_0000)
        #expect(SeedEntry.parse("7a3f9c2e") == 0x7A3F_9C2E_0000_0000)
        #expect(SeedEntry.parse("7A3F 9C2E") == 0x7A3F_9C2E_0000_0000)
    }

    @Test("what the popover is prefilled with parses back to the same seed under either spelling")
    func exactTextRoundTrips() {
        for seed: UInt64 in [0, 0x2A, 0x7A3F_9C2E_1234_5678, .max] {
            #expect(SeedEntry.parse(SeedFormat.hex.exactText(seed)) == seed)
            #expect(SeedEntry.parse(SeedFormat.decimal.exactText(seed)) == seed)
        }
    }

    @Test("sixteen hex digits are the whole seed, with or without 0x")
    func fullHex() {
        #expect(SeedEntry.parse("0x7A3F9C2E12345678") == 0x7A3F_9C2E_1234_5678)
        #expect(SeedEntry.parse("7A3F9C2E12345678") == 0x7A3F_9C2E_1234_5678)
        #expect(SeedEntry.parse("0x0000002a") == 0x2A << 32)
    }

    @Test("eight decimal digits are decimal, not a label")
    func eightDigitsAreDecimal() {
        #expect(SeedEntry.parse("12345678") == 12_345_678)
    }

    @Test("anything else is refused rather than guessed at",
          arguments: ["", "  ", "-1", "18446744073709551616", "abc", "0x", "7A3F9C2E1", "12 34", "seed 42", "1e5"])
    func refused(text: String) {
        #expect(SeedEntry.parse(text) == nil)
    }
}
