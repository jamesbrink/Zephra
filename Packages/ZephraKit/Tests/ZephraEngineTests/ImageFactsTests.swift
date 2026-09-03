import Foundation
import Testing
import ZephraCore

@testable import ZephraEngine

/// The six lines the inspector shows, and the one of them with rules worth pinning.
@Suite("The facts about one image, as the inspector reads them")
struct ImageFactsTests {
    @Test("a library image reads its facts out of its record")
    func factsFromAnItem() {
        let item = LibraryFilteringTests.item(prompt: "a lighthouse", seed: 0xABCD_1234_5678_9ABC)
        let facts = ImageFacts(item, modelName: "Z-Image Turbo")

        #expect(facts.model == "Z-Image Turbo")
        #expect(facts.size == "1024 \u{00D7} 1024")
        #expect(facts.steps == "9")
        #expect(facts.seed == "ABCD\u{00B7}1234")
        #expect(facts.file == item.fileName)
        #expect(facts.took == "\(Self.number(3)) s \u{00B7} \(Self.number(3.0 / 9)) s/step")
    }

    @Test("without a name for the model, the identifier in the file is shown")
    func unknownModelsShowTheirIdentifier() {
        let item = LibraryFilteringTests.item(prompt: "from an old build", modelID: "gone/for-good")
        #expect(ImageFacts(item).model == "gone/for-good")
    }

    @Test("an image that has not been saved says so, and takes its facts from its settings")
    func factsFromAnImageInMemory() {
        let image = GeneratedImage(
            pngData: Data(),
            settings: GenerationSettings(
                prompt: "a harbour", size: ImageSize(width: 1328, height: 1328), steps: 4,
                guidance: 0, seed: 42),
            modelID: "qwen-image-2512-4bit",
            duration: .seconds(66.7)
        )
        let facts = ImageFacts(image, modelName: "Qwen-Image")

        #expect(facts.model == "Qwen-Image")
        #expect(facts.size == "1328 \u{00D7} 1328")
        #expect(facts.steps == "4")
        // The label is the seed's leading eight hex digits, so a small seed reads as zeroes.
        #expect(facts.seed == "0000\u{00B7}0000")
        #expect(facts.file == "Not saved yet")
        #expect(facts.took == "\(Self.number(66.7)) s \u{00B7} \(Self.number(66.7 / 4)) s/step")
    }

    @Test("how long it took: nothing, seconds, minutes, and with no steps to divide by")
    func tookLabels() {
        #expect(ImageFacts.tookLabel(seconds: 0, steps: 4) == "\u{2014}")
        #expect(ImageFacts.tookLabel(seconds: -1, steps: 4) == "\u{2014}")
        #expect(
            ImageFacts.tookLabel(seconds: 33.6, steps: 4)
                == "\(Self.number(33.6)) s \u{00B7} \(Self.number(8.4)) s/step")
        #expect(ImageFacts.tookLabel(seconds: 33.6, steps: 0) == "\(Self.number(33.6)) s")
        // Past ten minutes the figure is minutes; the per-step one stays in seconds.
        #expect(
            ImageFacts.tookLabel(seconds: 660, steps: 4)
                == "\(Self.number(11)) min \u{00B7} \(Self.number(165)) s/step")
        #expect(ImageFacts.tookLabel(seconds: 600, steps: 0) == "\(Self.number(600)) s")
    }

    /// The same formatting the facts use, so these assertions hold in any locale.
    private static func number(_ value: Double) -> String {
        value.formatted(.number.precision(.fractionLength(1)))
    }
}
