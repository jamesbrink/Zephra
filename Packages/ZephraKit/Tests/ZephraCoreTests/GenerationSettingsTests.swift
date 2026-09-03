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
        let moved = settings.onSchedule(of: ModelCatalog.qwenImage2512_4bit)
        #expect(moved.referenceImage == settings.referenceImage)
        #expect(moved.size == settings.size)
    }

    @Test("a reference image alone is not enough to generate; the prompt still is what is required")
    func referenceDoesNotMakeReady() {
        var settings = GenerationSettings.defaults(for: descriptor)
        settings.referenceImage = Data([9, 9])
        #expect(!settings.isReadyToGenerate)
    }
}
