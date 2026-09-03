import Foundation
import QwenImage
import Testing
import ZephraCore

@testable import ZephraBackendQwenImage

@Suite("QwenImageRequestMapper")
struct QwenImageRequestMapperTests {
    private let descriptor = ModelCatalog.qwenImage2512_4bit

    private func settings(
        prompt: String = "a quiet room",
        size: ImageSize = ImageSize(width: 1024, height: 1024),
        steps: Int = 4,
        guidance: Double = 0,
        seed: UInt64 = 42
    ) -> GenerationSettings {
        GenerationSettings(
            prompt: prompt, negativePrompt: nil, size: size, steps: steps, guidance: guidance,
            seed: seed)
    }

    private func request(_ settings: GenerationSettings) -> QwenImageGenerationRequest {
        QwenImageRequestMapper.request(for: settings, descriptor: descriptor)
    }

    @Test("settings that already fit the model pass through untouched")
    func acceptableSettingsSurvive() {
        let made = request(settings())
        #expect(made.prompt == "a quiet room")
        #expect(made.width == 1024)
        #expect(made.height == 1024)
        #expect(made.steps == 4)
        #expect(made.seed == 42)
    }

    @Test("sizes are pulled onto the model's grid and inside its range")
    func sizesAreAlignedAndBounded() {
        let alignment = descriptor.capabilities.sizeAlignment
        let odd = request(settings(size: ImageSize(width: 1020, height: 780)))
        #expect(odd.width % alignment == 0 && odd.height % alignment == 0)
        #expect(odd.width == 1024)

        let bounds = descriptor.capabilities.sizeBounds
        let large = request(settings(size: ImageSize(width: 9000, height: 9000)))
        #expect(large.width == bounds.upperBound && large.height == bounds.upperBound)
        let small = request(settings(size: ImageSize(width: 8, height: 8)))
        #expect(small.width == bounds.lowerBound && small.height == bounds.lowerBound)
    }

    @Test("step counts are clamped to the distilled schedule's range")
    func stepsAreClamped() {
        let bounds = descriptor.capabilities.stepBounds
        #expect(request(settings(steps: 500)).steps == bounds.upperBound)
        #expect(request(settings(steps: 0)).steps == bounds.lowerBound)
    }

    @Test("the prompt-token cap is the descriptor's, so the catalog decides how much conditions")
    func promptCapComesFromTheDescriptor() {
        #expect(request(settings()).maxPromptTokens == descriptor.maxPromptTokens)
        #expect(request(settings()).maxPromptTokens == 512)
    }
}
