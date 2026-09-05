import Foundation
import Testing
import ZephraCore

@testable import Zephra

@Suite("The file name an export suggests")
struct SuggestedFileNameTests {
    private func image(prompt: String, seed: UInt64 = 42) -> GeneratedImage {
        GeneratedImage(
            pngData: Data(),
            settings: GenerationSettings(
                prompt: prompt, size: ImageSize(width: 512, height: 512), steps: 4,
                guidance: 0, seed: seed),
            modelID: "test", duration: .seconds(1))
    }

    @Test("the prompt's first five words and the seed, lowercased and hyphenated")
    func firstFiveWordsAndTheSeed() {
        let name = ImageExport.suggestedFileName(
            for: image(prompt: "A Quiet Street at Night, in the rain", seed: 7))
        #expect(name == "a-quiet-street-at-night-7.png")
    }

    @Test("punctuation is dropped rather than carried into the name")
    func punctuationIsDropped() {
        let name = ImageExport.suggestedFileName(for: image(prompt: "  fog... (dense) / cold!  "))
        #expect(name == "fog-dense-cold-42.png")
    }

    @Test("an empty prompt still names the file")
    func emptyPromptFallsBackToZephra() {
        #expect(ImageExport.suggestedFileName(for: image(prompt: "")) == "zephra-42.png")
        #expect(ImageExport.suggestedFileName(for: image(prompt: "?!")) == "zephra-42.png")
    }
}
