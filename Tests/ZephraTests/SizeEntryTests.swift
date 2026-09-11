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
        let groups = SizeChoice.grouped(Self.capabilities, picture: nil)
        #expect(groups.map(\.tier) == [.faster, .standard])
        #expect(groups.first?.choices.map(\.size).contains(ImageSize(width: 512, height: 320)) == true)
        #expect(groups.last?.choices.first?.size == ImageSize(width: 768, height: 512))
        let marked = groups.flatMap(\.choices).filter(\.matchesPicture)
        #expect(marked.isEmpty)
        let qwen = SizeChoice.grouped(ModelCatalog.qwenImage2512_4bit.capabilities, picture: nil)
        #expect(qwen.map(\.tier) == [.faster, .standard, .larger])
    }

    @Test("with a picture in the well each tier leads with the picture's shape at that tier's cost")
    func pictureShape() {
        let wan = ModelCatalog.wan22TI2V5B4bit.capabilities
        let groups = SizeChoice.grouped(wan, picture: ImageSize(width: 1500, height: 2000))
        #expect(groups.map(\.tier) == [.faster, .standard, .larger])
        let leads = groups.compactMap(\.choices.first)
        let unmarked = leads.filter { !$0.matchesPicture }
        #expect(unmarked.isEmpty)
        // 640 x 352, 832 x 480 and 1280 x 704 pixels, each as a 3:4 frame on the 32 grid.
        #expect(leads.map(\.size) == [
            ImageSize(width: 416, height: 544), ImageSize(width: 544, height: 736),
            ImageSize(width: 832, height: 1088),
        ])
        #expect(leads.first?.label == "416 × 544 · Matches Picture")
        #expect(groups.flatMap(\.choices).filter(\.matchesPicture).count == 3)
    }

    @Test("a picture whose shape is a preset marks the preset instead of repeating it")
    func pictureIsPreset() {
        let groups = SizeChoice.grouped(Self.capabilities, picture: ImageSize(width: 3000, height: 2000))
        let standard = groups.first { $0.tier == .standard }?.choices ?? []
        #expect(standard.filter { $0.size == ImageSize(width: 768, height: 512) }.count == 1)
        #expect(standard.first { $0.size == ImageSize(width: 768, height: 512) }?.matchesPicture == true)
        #expect(standard.first?.size == ImageSize(width: 768, height: 512))
    }
}
