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

    @Test("settings survive a round trip through JSON")
    func codableRoundTrip() throws {
        var settings = GenerationSettings.defaults(for: descriptor)
        settings.prompt = "a lighthouse at dusk"

        let data = try JSONEncoder().encode(settings)
        let decoded = try JSONDecoder().decode(GenerationSettings.self, from: data)
        #expect(decoded == settings)
    }
}
