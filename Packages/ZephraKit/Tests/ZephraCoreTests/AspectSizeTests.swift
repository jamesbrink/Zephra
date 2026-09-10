import Testing
import ZephraCore

/// Picking the size to animate a picture at: its own shape, at the pixel budget in force.
@Suite("The size matching a picture's shape")
struct AspectSizeTests {
    private static let video = capabilities(bounds: 256...1024)
    /// 768 × 512, the budget a clip model's default frame gives.
    private static let budget = 768 * 512

    @Test("a landscape picture keeps its shape at the budget, on the grid")
    func landscape() {
        let size = Self.video.size(matchingAspectOf: ImageSize(width: 1600, height: 1200), budget: Self.budget)
        // 4:3 at 393,216 pixels is 724 × 543; the grid makes it 736 × 544.
        #expect(size == ImageSize(width: 736, height: 544))
    }

    @Test("a widescreen picture is wider than any preset would have made it")
    func widescreen() {
        let size = Self.video.size(matchingAspectOf: ImageSize(width: 1920, height: 1080), budget: Self.budget)
        #expect(size == ImageSize(width: 832, height: 480))
    }

    @Test("a portrait picture comes out portrait")
    func portrait() throws {
        let size = try #require(
            Self.video.size(matchingAspectOf: ImageSize(width: 1080, height: 1920), budget: Self.budget))
        #expect(size.width < size.height)
        #expect(size == ImageSize(width: 480, height: 832))
    }

    @Test("a square picture is square")
    func square() {
        let size = Self.video.size(matchingAspectOf: ImageSize(width: 1024, height: 1024), budget: Self.budget)
        #expect(size == ImageSize(width: 640, height: 640))
    }

    @Test("a smaller budget makes a smaller frame of the same shape")
    func smallerBudget() {
        let size = Self.video.size(matchingAspectOf: ImageSize(width: 1600, height: 1200), budget: 512 * 288)
        #expect(size == ImageSize(width: 448, height: 320))
    }

    @Test("a shape that would fall under the lower bound is scaled up whole, not clamped on one edge")
    func lowerBound() {
        let size = Self.video.size(matchingAspectOf: ImageSize(width: 3000, height: 1000), budget: 512 * 288)
        // 3:1 at 147,456 pixels is 665 × 222; scaled so the short edge reaches 256 it is
        // 768 × 256, and both are on the grid.
        #expect(size == ImageSize(width: 768, height: 256))
    }

    @Test("a shape that would exceed the upper bound is scaled down whole")
    func upperBound() {
        let size = Self.video.size(matchingAspectOf: ImageSize(width: 3000, height: 1000), budget: 1024 * 1024)
        #expect(size == ImageSize(width: 1024, height: 352))
    }

    @Test("a picture with no shape, or no budget, answers nothing")
    func nothing() {
        #expect(Self.video.size(matchingAspectOf: ImageSize(width: 0, height: 100), budget: Self.budget) == nil)
        #expect(Self.video.size(matchingAspectOf: ImageSize(width: 100, height: 0), budget: Self.budget) == nil)
        #expect(Self.video.size(matchingAspectOf: ImageSize(width: 100, height: 100), budget: 0) == nil)
    }

    private static func capabilities(bounds: ClosedRange<Int>) -> ModelCapabilities {
        ModelCapabilities(
            sizeAlignment: 32,
            sizePresets: [ImageSize(width: 768, height: 512)],
            sizeBounds: bounds,
            defaultSize: ImageSize(width: 768, height: 512),
            stepBounds: 8...8,
            defaultSteps: 8,
            guidanceBounds: 0...0,
            defaultGuidance: 0,
            supportsNegativePrompt: false,
            supportsSeed: true
        )
    }
}
