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
        #expect(facts.took == "3 s \u{00B7} \(Self.number(3.0 / 9)) s/step")
    }

    @Test("the Seed row follows the format it was asked for")
    func seedFollowsTheFormat() {
        let seed: UInt64 = 0x7A3F_9C2E_0000_0042
        let item = LibraryFilteringTests.item(prompt: "a lighthouse", seed: seed)
        #expect(ImageFacts(item).seed == "7A3F\u{00B7}9C2E")
        #expect(ImageFacts(item, seedFormat: .decimal).seed == "8808931117542408258")
        #expect(ImageFacts.seedLabel(nil, as: .decimal) == ImageFacts.unknown)
    }

    @Test("a clip carried on names its source and how many frames were held")
    func continuedClip() {
        #expect(ImageFacts.continuedLabel(from: "a.png", held: 9) == "a.png, 9 frames held")
        #expect(ImageFacts.continuedLabel(from: "a.png", held: 1) == "a.png, from its last frame")
        let item = LibraryFilteringTests.item(prompt: "a lighthouse", seed: 1)
        #expect(ImageFacts(item).continued == nil)
    }

    @Test("a clip's length reads as seconds, frames and rate; a picture has none")
    func lengthOfAClip() {
        #expect(ImageFacts.lengthLabel(frames: 49, rate: 24) == "2.0 s, 49 frames at 24 fps", "49 frames is 2.04 s, not two")
        #expect(ImageFacts.lengthLabel(frames: 9, rate: 24) == "0.4 s, 9 frames at 24 fps")
        #expect(ImageFacts.lengthLabel(frames: 121, rate: 24) == "5.0 s, 121 frames at 24 fps")
        #expect(ImageFacts.lengthLabel(frames: 49, rate: 24, sound: true) == "2.0 s, 49 frames at 24 fps, with sound")
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
        #expect(facts.took == "1 min 7 s \u{00B7} \(Self.number(66.7 / 4)) s/step")
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
                == "11 min \u{00B7} \(Self.number(165)) s/step")
        #expect(ImageFacts.tookLabel(seconds: 600, steps: 0) == "10 min")
        #expect(ImageFacts.tookLabel(seconds: 80, steps: 0) == "1 min 20 s")
    }

    @Test("an edit says how far from its picture it started, and which picture that was")
    func referenceRows() {
        var record = Self.record()
        record.referenceBytes = 44
        record.referenceStrength = 0.6
        record.referenceOrigin = "harbour-1234.png"
        let facts = ImageFacts(Self.item(record))

        #expect(facts.referenceStrength == Self.strength(0.6))
        #expect(facts.referenceStrengthValue == 0.6)
        #expect(facts.referenceOrigin == "harbour-1234.png")
    }

    @Test("a generation with no picture, and one that had no distance to travel, say nothing")
    func noReferenceRows() {
        #expect(ImageFacts(Self.item(Self.record())).referenceStrength == nil)
        #expect(ImageFacts(Self.item(Self.record())).referenceOrigin == nil)

        // What klein writes: a picture conditioned on directly, recorded at 1.
        var direct = Self.record()
        direct.referenceBytes = 44
        direct.referenceStrength = 1
        #expect(ImageFacts(Self.item(direct)).referenceStrength == nil, "1.00 says nothing")
        #expect(ImageFacts(Self.item(direct)).referenceStrengthValue == nil)
    }

    @Test("a clip's own strength is reported as the number, for the caller to word")
    func aClipsStrength() {
        var record = Self.record()
        record.referenceBytes = 44
        record.referenceStrength = 0
        record.frameCount = 49
        record.frameRate = 24
        let facts = ImageFacts(Self.item(record))

        // LTX-2.5 runs the scale the other way: 0 holds the first frame exactly. The engine
        // formats the number and says it is a clip; wording that as a phrase is the app's.
        #expect(facts.referenceStrengthValue == 0)
        #expect(facts.referenceStrength == Self.strength(0))
        #expect(facts.length == "2.0 s, 49 frames at 24 fps")
    }

    @Test("a picture still in memory reads its reference rows from its settings")
    func referenceRowsFromAnImageInMemory() {
        var settings = GenerationSettings(
            prompt: "make it night", size: ImageSize(width: 1024, height: 1024), steps: 9,
            guidance: 3, seed: 42)
        settings.referenceImage = Data([1, 2, 3])
        settings.referenceStrength = 0.45
        settings.referenceOrigin = "harbour-1234.png"
        let image = GeneratedImage(
            pngData: Data(), settings: settings, modelID: ModelCatalog.default.id,
            duration: .seconds(3))
        let facts = ImageFacts(image)

        #expect(facts.referenceStrength == Self.strength(0.45))
        #expect(facts.referenceOrigin == "harbour-1234.png")

        settings.referenceImage = nil
        let plain = GeneratedImage(
            pngData: Data(), settings: settings, modelID: ModelCatalog.default.id,
            duration: .seconds(3))
        #expect(ImageFacts(plain).referenceStrength == nil, "no picture, nothing to report")
        #expect(ImageFacts(plain).referenceOrigin == nil)
    }

    @Test("transparency is read off the file, and off the bytes for a picture not yet saved")
    func transparencyComesFromTheHeader() {
        let opaque = LibraryItem(
            url: URL(filePath: "/Zephra/solid.png"), collection: .generated,
            provenance: .generated(Self.record()), fileSize: 4096, contentModifiedAt: .now,
            hasAlpha: false)
        let clear = LibraryItem(
            url: URL(filePath: "/Zephra/clear.png"), collection: .generated,
            provenance: .generated(Self.record()), fileSize: 4096, contentModifiedAt: .now,
            hasAlpha: true)

        #expect(!ImageFacts(opaque).isTransparent)
        #expect(ImageFacts(clear).isTransparent)

        // The fixture every backend test writes is an RGBA PNG; a picture with no bytes at all
        // has no header to read and says no rather than throwing.
        let made = GeneratedImage(
            pngData: MockBackend.pngData,
            settings: GenerationSettings(
                prompt: "a lighthouse", size: ImageSize(width: 1, height: 1), steps: 9,
                guidance: 3, seed: 42),
            modelID: ModelCatalog.default.id, duration: .seconds(3))
        #expect(ImageFacts(made).isTransparent)
        #expect(!ImageFacts(GeneratedImage(
            pngData: Data(), settings: made.settings, modelID: made.modelID,
            duration: .seconds(3))).isTransparent)
    }

    /// A plain generated record, for a test that then says what is different about it.
    private static func record() -> GenerationRecord {
        GenerationRecord(
            GeneratedImage(
                pngData: Data(),
                settings: GenerationSettings(
                    prompt: "a lighthouse", size: ImageSize(width: 1024, height: 1024), steps: 9,
                    guidance: 3, seed: 42),
                modelID: ModelCatalog.default.id,
                duration: .seconds(3)))
    }

    /// The same formatting the strength row uses, so these assertions hold in any locale.
    private static func strength(_ value: Double) -> String {
        value.formatted(.number.precision(.fractionLength(2)))
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
