import Testing
import ZephraCore

@testable import Zephra

/// How the Size menu groups a model's presets, and what the well's picture does to them.
@Suite("Grouping the sizes a model offers")
struct SizeChoiceTests {
    private static let capabilities = ModelCatalog.ltx2Distilled4bit.capabilities

    @Test("the menu groups presets by tier, faster first, and skips empty tiers")
    func grouping() {
        let groups = SizeChoice.grouped(Self.capabilities, picture: nil)
        #expect(groups.map(\.tier) == [.faster, .standard])
        #expect(groups.first?.choices.map(\.size).contains(ImageSize(width: 512, height: 320)) == true)
        #expect(groups.last?.choices.first?.size == ImageSize(width: 768, height: 512))
        let marked = groups.flatMap(\.choices).filter(\.matchesPicture)
        #expect(marked.isEmpty)
        let klein = SizeChoice.grouped(ModelCatalog.flux2Klein4bit.capabilities, picture: nil)
        #expect(klein.map(\.tier) == [.faster, .standard, .larger])
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
