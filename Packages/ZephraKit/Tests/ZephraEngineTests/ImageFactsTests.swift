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

    @Test("a clip's length reads as seconds, frames and rate; a picture has none")
    func lengthOfAClip() {
        #expect(ImageFacts.lengthLabel(frames: 49, rate: 24) == "2.0 s, 49 frames at 24 fps")
        #expect(ImageFacts.lengthLabel(frames: 121, rate: 24) == "5.0 s, 121 frames at 24 fps")
        let item = LibraryFilteringTests.item(prompt: "a lighthouse", seed: 1)
        #expect(ImageFacts(item).length == nil)
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

    @Test("a picture made larger says so, and by how much and from what")
    func upscaledReadsItsProvenance() {
        var record = GenerationRecord.upscaled(
            from: nil, parentFileName: "holiday.png", factor: 4,
            size: ImageSize(width: 4096, height: 3072), duration: .seconds(2))
        let facts = ImageFacts(Self.item(record), modelName: "Real-ESRGAN")

        #expect(facts.upscaled == "\u{00D7}4 from holiday.png")
        // Nothing generated it, so nothing is claimed about how it was.
        #expect(facts.steps == ImageFacts.unknown)
        #expect(facts.seed == ImageFacts.unknown)
        #expect(facts.size == "4096 \u{00D7} 3072")

        record.upscaleFactor = nil
        record.upscaledFrom = nil
        #expect(ImageFacts(Self.item(record)).upscaled == nil)
    }

    @Test("an upscale of a generated picture keeps the steps but not a per-step time")
    func upscaledTookHasNoPerStepFigure() {
        var parent = GenerationRecord.upscaled(
            from: nil, parentFileName: "a.png", factor: 2,
            size: ImageSize(width: 8, height: 8), duration: .seconds(1))
        parent.steps = 9
        parent.upscaleFactor = nil
        parent.upscaledFrom = nil
        let record = GenerationRecord.upscaled(
            from: parent, parentFileName: "a.png", factor: 4,
            size: ImageSize(width: 32, height: 32), duration: .seconds(4.6))
        let facts = ImageFacts(Self.item(record))

        #expect(facts.steps == "9")
        // 4.6 s over the parent's nine steps would be a figure that was never true.
        #expect(facts.took == "4.6 s")
    }

    @Test("an image still in memory claims no upscale, because it has no record to read one from")
    func aFreshPictureClaimsNothing() {
        let image = GeneratedImage(
            pngData: Data(),
            settings: GenerationSettings(
                prompt: "", size: ImageSize(width: 2048, height: 2048), steps: 0, guidance: 0,
                seed: 0),
            modelID: "real-esrgan-x2",
            duration: .seconds(1))
        let facts = ImageFacts(image)

        #expect(facts.upscaled == nil)
        #expect(facts.steps == ImageFacts.unknown)
        #expect(facts.seed == ImageFacts.unknown)
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

    /// One library item carrying exactly the record handed in.
    private static func item(_ record: GenerationRecord) -> LibraryItem {
        LibraryItem(
            url: URL(filePath: "/Zephra/holiday-x4.png"),
            collection: .generated,
            provenance: .generated(record),
            annotation: LibraryAnnotation(),
            fileSize: 4096,
            contentModifiedAt: record.createdAt)
    }

    /// The same formatting the facts use, so these assertions hold in any locale.
    private static func number(_ value: Double) -> String {
        value.formatted(.number.precision(.fractionLength(1)))
    }
}
