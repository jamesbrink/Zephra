import Testing
import ZephraCore

@testable import ZephraMobile

/// What the Size menu offers, which is a pure question about a model and a picture.
@Suite("The Size menu offers the model's sizes, grouped by what they cost")
struct SizeOptionsTests {
    /// A model with presets either side of its default, so all three tiers have something.
    private func capabilities(alignment: Int = 64, video: Bool = false) -> ModelCapabilities {
        ModelCapabilities(
            sizeAlignment: alignment,
            sizePresets: [
                ImageSize(width: 1024, height: 1024),
                ImageSize(width: 768, height: 768),
                ImageSize(width: 1536, height: 1536),
            ],
            sizeBounds: 256...2048,
            defaultSize: ImageSize(width: 1024, height: 1024),
            stepBounds: 1...20,
            defaultSteps: 9,
            guidanceBounds: 0...0,
            defaultGuidance: 0,
            supportsNegativePrompt: false,
            supportsSeed: true,
            supportsReferenceImage: true,
            frameBounds: video ? 9...121 : 1...1,
            defaultFrames: video ? 49 : 1,
            frameAlignment: 8)
    }

    @Test("Every preset lands in a tier, faster first")
    func presetsAreGroupedByCost() {
        let grouped = SizeOptions.grouped(capabilities: capabilities(), reference: nil)
        #expect(grouped.map(\.tier) == [.faster, .standard, .larger])
        #expect(grouped.flatMap(\.choices).map(\.size.pixelCount).count == 3)
        #expect(grouped.allSatisfy { $0.choices.allSatisfy { !$0.matchesPicture } })
    }

    @Test("A picture in the well leads every tier with its own shape")
    func thePicturesShapeLeadsEachTier() throws {
        let grouped = SizeOptions.grouped(
            capabilities: capabilities(), reference: ImageSize(width: 1600, height: 900))
        for group in grouped {
            let first = try #require(group.choices.first)
            #expect(first.matchesPicture)
            #expect(first.size.width > first.size.height)
            #expect(first.size.width % 64 == 0 && first.size.height % 64 == 0)
        }
    }

    @Test("A tier's shape costs about what that tier's own preset costs")
    func theShapeKeepsTheTiersCost() throws {
        let model = capabilities()
        let grouped = SizeOptions.grouped(
            capabilities: model, reference: ImageSize(width: 1600, height: 900))
        let faster = try #require(grouped.first { $0.tier == .faster })
        let shape = try #require(faster.choices.first)
        #expect(model.tier(of: shape.size) == .faster)
    }

    @Test("A square picture marks the square preset rather than repeating it")
    func aShapeAlreadyOfferedIsNotOfferedTwice() {
        let grouped = SizeOptions.grouped(
            capabilities: capabilities(), reference: ImageSize(width: 1024, height: 1024))
        let sizes = grouped.flatMap(\.choices).map(\.size)
        #expect(sizes.count == Set(sizes).count)
        #expect(grouped.flatMap(\.choices).contains { $0.matchesPicture })
    }

    @Test("A row says it matches the picture in the words the Mac uses")
    func theRowSaysSo() {
        let choice = SizeChoice(size: ImageSize(width: 1216, height: 704), matchesPicture: true)
        #expect(choice.label == "1216 × 704 · Matches Picture")
        #expect(SizeChoice(size: choice.size, matchesPicture: false).label == "1216 × 704")
    }
}
