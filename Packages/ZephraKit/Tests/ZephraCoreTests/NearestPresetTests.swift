import Testing
import ZephraCore

/// Picking the size to animate a picture at: the offered preset whose shape is nearest its own.
@Suite("The preset nearest a picture's shape")
struct NearestPresetTests {
    /// A stand-in for a clip model's list: landscape first, then a wider one, then portrait.
    private static let video = capabilities(presets: [
        ImageSize(width: 768, height: 512),
        ImageSize(width: 512, height: 288),
        ImageSize(width: 512, height: 768),
    ])

    @Test("a landscape picture picks the landscape preset")
    func landscape() {
        let picked = Self.video.preset(nearestAspect: ImageSize(width: 1600, height: 1000))
        #expect(picked == ImageSize(width: 768, height: 512))
    }

    @Test("a widescreen picture picks the widest preset, not merely a landscape one")
    func widescreen() {
        let picked = Self.video.preset(nearestAspect: ImageSize(width: 1920, height: 1080))
        #expect(picked == ImageSize(width: 512, height: 288), "16:9 is 16:9")
    }

    @Test("a portrait picture picks the portrait preset")
    func portrait() {
        let picked = Self.video.preset(nearestAspect: ImageSize(width: 1000, height: 1500))
        #expect(picked == ImageSize(width: 512, height: 768))
    }

    @Test("a square picture picks the preset nearest square, and a tie goes to the earlier one")
    func squareish() {
        // 768 x 512 is 3:2 and 512 x 768 is 2:3 — the same distance from square in log space,
        // so the earlier one wins. 512 x 288 is 16:9 and is further from square than either.
        let picked = Self.video.preset(nearestAspect: ImageSize(width: 1024, height: 1024))
        #expect(picked == ImageSize(width: 768, height: 512))
    }

    @Test("a model offering one size answers with it whatever the picture's shape")
    func onePreset() {
        let one = Self.capabilities(presets: [ImageSize(width: 1024, height: 1024)])
        #expect(
            one.preset(nearestAspect: ImageSize(width: 400, height: 1600))
                == ImageSize(width: 1024, height: 1024))
    }

    @Test("a model offering no sizes, or a picture with no shape, answers nothing")
    func nothingToPick() {
        let none = Self.capabilities(presets: [])
        #expect(none.preset(nearestAspect: ImageSize(width: 100, height: 100)) == nil)
        #expect(Self.video.preset(nearestAspect: ImageSize(width: 0, height: 100)) == nil)
        #expect(Self.video.preset(nearestAspect: ImageSize(width: 100, height: 0)) == nil)
    }

    @Test("a picture model's own presets pick sanely too")
    func aPictureModelsPresets() throws {
        let capabilities = ModelCatalog.default.capabilities
        let tall = try #require(capabilities.preset(nearestAspect:
            ImageSize(width: 832, height: 1216)))
        #expect(tall.width < tall.height, "a tall picture picks a tall preset")
        let wide = try #require(capabilities.preset(nearestAspect:
            ImageSize(width: 1216, height: 832)))
        #expect(wide.width > wide.height)
        let square = try #require(capabilities.preset(nearestAspect:
            ImageSize(width: 900, height: 900)))
        #expect(square == ImageSize(width: 1024, height: 1024))
    }

    private static func capabilities(presets: [ImageSize]) -> ModelCapabilities {
        ModelCapabilities(
            sizeAlignment: 32,
            sizePresets: presets,
            sizeBounds: 256...1024,
            defaultSize: presets.first ?? ImageSize(width: 512, height: 512),
            stepBounds: 8...8,
            defaultSteps: 8,
            guidanceBounds: 0...0,
            defaultGuidance: 0,
            supportsNegativePrompt: false,
            supportsSeed: true
        )
    }
}
