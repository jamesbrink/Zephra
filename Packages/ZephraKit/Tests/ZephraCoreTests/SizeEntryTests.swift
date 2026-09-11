import Testing
import ZephraCore

/// Reading a size a person typed into the Size menu's field.
@Suite("Typing a size")
struct SizeEntryTests {
    private static let capabilities = ModelCatalog.ltx2Distilled4bit.capabilities

    @Test("two numbers with anything between them are a size, width first")
    func spellings() {
        for text in ["800 × 512", "800x512", "800 by 512", "800, 512", " 800×512 ", "800 512"] {
            #expect(SizeEntry.typed(text) == ImageSize(width: 800, height: 512), "\(text)")
        }
    }

    @Test("one number, three numbers, or a zero is not a size")
    func refused() {
        for text in ["800", "800 × 512 × 3", "0 × 512", "", "wide"] {
            #expect(SizeEntry.typed(text) == nil, "\(text)")
        }
    }

    @Test("a typed size lands on the model's grid and inside its bounds")
    func fitted() {
        #expect(SizeEntry.parse("800 × 500", for: Self.capabilities) == ImageSize(width: 832, height: 512))
        #expect(SizeEntry.parse("4000 × 100", for: Self.capabilities) == ImageSize(width: 1024, height: 256))
        #expect(SizeEntry.parse("nothing", for: Self.capabilities) == nil)
    }

    @Test("the field spells a size the way the menu does, and the rule names the grid")
    func spelling() {
        #expect(SizeEntry.text(ImageSize(width: 768, height: 512)) == "768 × 512")
        #expect(SizeEntry.rule(for: Self.capabilities) == "Multiples of 64, from 256 to 1024.")
    }
}
