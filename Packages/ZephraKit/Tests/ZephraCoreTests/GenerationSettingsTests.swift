import Foundation
import Testing

@testable import ZephraCore

@Suite("GenerationSettings")
struct GenerationSettingsTests {
    private let descriptor = ModelCatalog.zImageTurbo8bit

    @Test("defaults come from the model's capabilities and an empty prompt")
    func defaultsUseCapabilities() {
        let settings = GenerationSettings.defaults(for: descriptor)
        let capabilities = descriptor.capabilities
        #expect(settings.prompt.isEmpty)
        #expect(settings.negativePrompt == nil)
        #expect(settings.size == capabilities.defaultSize)
        #expect(settings.steps == capabilities.defaultSteps)
        #expect(settings.guidance == capabilities.defaultGuidance)
    }

    @Test("withRandomSeed changes the seed and nothing else")
    func randomSeedChangesOnlySeed() {
        var settings = GenerationSettings.defaults(for: descriptor)
        settings.prompt = "a lighthouse"
        settings.seed = 7

        let reseeded = settings.withRandomSeed()
        #expect(reseeded.seed != settings.seed)
        #expect(reseeded.prompt == settings.prompt)
        #expect(reseeded.size == settings.size)
    }

    @Test("a whitespace-only prompt is not ready to generate")
    func readinessIgnoresWhitespace() {
        var settings = GenerationSettings.defaults(for: descriptor)
        #expect(!settings.isReadyToGenerate)

        settings.prompt = "   \n\t "
        #expect(!settings.isReadyToGenerate)

        settings.prompt = "  a lighthouse  "
        #expect(settings.isReadyToGenerate)
    }

    @Test("settings survive a round trip through JSON, reference image included")
    func codableRoundTrip() throws {
        var settings = GenerationSettings.defaults(for: descriptor)
        settings.prompt = "a lighthouse at dusk"
        settings.referenceImage = Data([1, 2, 3, 4])

        let data = try JSONEncoder().encode(settings)
        let decoded = try JSONDecoder().decode(GenerationSettings.self, from: data)
        #expect(decoded == settings)
    }

    @Test("moving to another model's schedule keeps the reference image, as it keeps the size")
    func scheduleKeepsTheReference() {
        var settings = GenerationSettings.defaults(for: descriptor)
        settings.referenceImage = Data([9, 9])
        let moved = settings.onSchedule(of: ModelCatalog.zImageTurbo4bit)
        #expect(moved.referenceImage == settings.referenceImage)
        #expect(moved.size == settings.size)
    }

    @Test("a reference image alone is not enough to generate; the prompt still is what is required")
    func referenceDoesNotMakeReady() {
        var settings = GenerationSettings.defaults(for: descriptor)
        settings.referenceImage = Data([9, 9])
        #expect(!settings.isReadyToGenerate)
    }

    @Test("defaults carry a strength that changes nothing")
    func defaultsCarryANeutralStrength() {
        #expect(GenerationSettings.defaults(for: descriptor).referenceImage == nil)
        #expect(GenerationSettings.defaults(for: descriptor).referenceStrength == 1)
    }

    @Test("a strength survives the round trip, and settings written without one still decode")
    func strengthRoundTrip() throws {
        var settings = GenerationSettings.defaults(for: descriptor)
        settings.prompt = "a lighthouse at dusk"
        settings.referenceImage = Data([9, 9])
        settings.referenceStrength = 0.45

        let data = try JSONEncoder().encode(settings)
        let decoded = try JSONDecoder().decode(GenerationSettings.self, from: data)
        #expect(decoded == settings)
        #expect(decoded.referenceStrength == 0.45)

        // What a build that predates strength wrote: the key is simply absent. A synthesised
        // decoder would throw here, because a non-optional property does not fall back to its
        // initializer's default; the hand-written one reads the absence as "changes nothing".
        var older = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        older.removeValue(forKey: "referenceStrength")
        let olderData = try JSONSerialization.data(withJSONObject: older)
        let fromOlder = try JSONDecoder().decode(GenerationSettings.self, from: olderData)
        #expect(fromOlder.referenceStrength == 1)
        #expect(fromOlder.prompt == settings.prompt)
        #expect(fromOlder.referenceImage == settings.referenceImage)
    }

    @Test("the one-picture reads name the first of several")
    func theScalarsNameTheFirstPicture() {
        var settings = GenerationSettings.defaults(for: descriptor)
        settings.referenceImages = [
            ReferencePicture(data: Data([1]), origin: "one.png"),
            ReferencePicture(data: Data([2]), origin: "two.png"),
        ]
        #expect(settings.referenceImage == Data([1]))
        #expect(settings.referenceOrigin == "one.png")
    }

    @Test("setting the one picture replaces the strip, and nil empties it")
    func settingTheScalarReplacesTheStrip() {
        var settings = GenerationSettings.defaults(for: descriptor)
        settings.referenceImages = [
            ReferencePicture(data: Data([1]), origin: "one.png"),
            ReferencePicture(data: Data([2]), origin: "two.png"),
        ]
        settings.referenceImage = Data([3])
        #expect(settings.referenceImages == [ReferencePicture(data: Data([3]))])
        #expect(settings.referenceOrigin == nil, "a new picture brings its own provenance")

        settings.referenceImage = nil
        #expect(settings.referenceImages.isEmpty)
    }

    @Test("an origin written with no picture to be about is not kept")
    func anOriginNeedsAPicture() {
        var settings = GenerationSettings.defaults(for: descriptor)
        settings.referenceOrigin = "nothing.png"
        #expect(settings.referenceOrigin == nil)
        #expect(settings.referenceImages.isEmpty)

        settings.referenceImage = Data([1])
        settings.referenceOrigin = "harbour.png"
        #expect(settings.referenceImages.first?.origin == "harbour.png")
    }
}
