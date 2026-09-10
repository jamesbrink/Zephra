import Testing
import ZephraCore
@testable import Zephra

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

    @Test("the menu groups presets by tier, faster first, and skips empty tiers")
    func grouping() {
        let groups = SizeMenu.grouped(Self.capabilities)
        #expect(groups.map(\.tier) == [.faster, .standard])
        #expect(groups.first?.sizes.contains(ImageSize(width: 512, height: 320)) == true)
        #expect(groups.last?.sizes.first == ImageSize(width: 768, height: 512))
        let qwen = SizeMenu.grouped(ModelCatalog.qwenImage2512_4bit.capabilities)
        #expect(qwen.map(\.tier) == [.faster, .standard, .larger])
    }
}
