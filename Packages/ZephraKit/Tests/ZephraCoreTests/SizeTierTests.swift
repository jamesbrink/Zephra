import Testing
import ZephraCore

/// Grouping the offered sizes by what they cost against the default.
@Suite("Size tiers")
struct SizeTierTests {
    private static let capabilities = ModelCapabilities(
        sizeAlignment: 32,
        sizePresets: [],
        sizeBounds: 256...2048,
        defaultSize: ImageSize(width: 1024, height: 1024),
        stepBounds: 1...20,
        defaultSteps: 9,
        guidanceBounds: 0...0,
        defaultGuidance: 0,
        supportsNegativePrompt: false,
        supportsSeed: true
    )

    @Test("the default and its neighbours are standard")
    func standard() {
        #expect(Self.capabilities.tier(of: ImageSize(width: 1024, height: 1024)) == .standard)
        #expect(Self.capabilities.tier(of: ImageSize(width: 1344, height: 768)) == .standard)
        #expect(Self.capabilities.tier(of: ImageSize(width: 896, height: 896)) == .standard)
    }

    @Test("well under the default is faster")
    func faster() {
        #expect(Self.capabilities.tier(of: ImageSize(width: 768, height: 768)) == .faster)
        #expect(Self.capabilities.tier(of: ImageSize(width: 512, height: 512)) == .faster)
    }

    @Test("well over the default is larger")
    func larger() {
        #expect(Self.capabilities.tier(of: ImageSize(width: 1328, height: 1328)) == .larger)
        #expect(Self.capabilities.tier(of: ImageSize(width: 2048, height: 1024)) == .larger)
    }

    @Test("every tier has a heading")
    func headings() {
        #expect(Set(SizeTier.allCases.map(\.title)).count == SizeTier.allCases.count)
    }
}
