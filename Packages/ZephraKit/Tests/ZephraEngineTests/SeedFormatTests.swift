import Testing

@testable import ZephraEngine

/// The two spellings of a seed, and that the facts follow the one asked for.
@Suite("A seed is shown as a short hex label or as the whole number")
struct SeedFormatTests {
    private let seed: UInt64 = 0x7A3F_9C2E_0000_0042

    @Test("the hex label is the leading eight digits, split; the decimal is the whole number")
    func labels() {
        #expect(SeedFormat.hex.label(seed) == "7A3F\u{00B7}9C2E")
        #expect(SeedFormat.decimal.label(seed) == "8808931117542408258")
    }

    @Test("the exact text carries the whole seed in either spelling, padded to sixteen hex digits")
    func exactText() {
        #expect(SeedFormat.hex.exactText(seed) == "0x7A3F9C2E00000042")
        #expect(SeedFormat.hex.exactText(0x42) == "0x0000000000000042")
        #expect(SeedFormat.decimal.exactText(seed) == "8808931117542408258")
    }

    @Test("the inspector's Seed row follows the format it was asked for")
    func factsFollowTheFormat() {
        let item = LibraryFilteringTests.item(prompt: "a lighthouse", seed: seed)
        #expect(ImageFacts(item).seed == "7A3F\u{00B7}9C2E")
        #expect(ImageFacts(item, seedFormat: .decimal).seed == "8808931117542408258")
        #expect(ImageFacts.seedLabel(nil, as: .decimal) == ImageFacts.unknown)
    }
}
