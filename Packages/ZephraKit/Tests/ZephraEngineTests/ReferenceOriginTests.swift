import Foundation
import Testing
import ZephraCore

@testable import ZephraEngine

/// Where the reference picture came from, written beside it and read back with it.
@MainActor
@Suite("The library picture an edit started from")
struct ReferenceOriginTests {
    private static let picture = Data([0x89, 0x50, 0x4E, 0x47] + Array(repeating: 0x2A, count: 40))
    private static let editing = ModelCatalog.default

    @Test("an edit records the file it started from, and reads it back")
    func originRoundTrip() throws {
        let image = Self.image(origin: "harbour-1234.png")
        let data = try GenerationRecord.embedded(in: image)
        let record = try #require(GenerationRecord.read(from: data))

        #expect(record.version == GenerationRecord.currentVersion, "still version 1")
        #expect(record.referenceOrigin == "harbour-1234.png")
        #expect(record.image(pngData: data, fileURL: nil, referenceImage: Self.picture)
            .settings.referenceOrigin == "harbour-1234.png")
    }

    @Test("a picture chosen from a file or dropped in records no origin")
    func noOrigin() throws {
        let data = try GenerationRecord.embedded(in: Self.image(origin: nil))
        let record = try #require(GenerationRecord.read(from: data))
        #expect(record.referenceBytes == Self.picture.count, "there was a picture")
        #expect(record.referenceOrigin == nil, "but nothing to say where it came from")
    }

    @Test("a generation with no picture records no origin, whatever the settings carried")
    func noPictureNoOrigin() throws {
        var settings = GenerationSettings.defaults(for: Self.editing)
        settings.prompt = "a lighthouse"
        settings.referenceOrigin = "left-behind.png"
        let image = GeneratedImage(
            pngData: MockBackend.pngData, settings: settings, modelID: Self.editing.id,
            duration: .seconds(1))
        #expect(GenerationRecord(image).referenceOrigin == nil)
    }

    @Test("a record written before origins existed reads back without one")
    func olderRecordsDecode() throws {
        // The JSON an older build wrote, key for key, with no `referenceOrigin` in it.
        let json = """
            {"version":1,"prompt":"a lighthouse","width":1024,"height":1024,"steps":9,
             "guidance":3,"seed":42,"modelID":"z-image-turbo-8bit",
             "createdAt":768000000,"durationSeconds":3,"referenceBytes":44,
             "referenceStrength":0.6}
            """
        let record = try JSONDecoder().decode(GenerationRecord.self, from: Data(json.utf8))
        #expect(record.referenceOrigin == nil)
        #expect(record.referenceStrength == 0.6, "and everything it did carry is unchanged")
        #expect(record.settings().referenceOrigin == nil)
    }

    @Test("settings written before origins existed decode without one")
    func olderSettingsDecode() throws {
        let json = """
            {"prompt":"a lighthouse","size":{"width":1024,"height":1024},"steps":9,
             "guidance":3,"seed":42}
            """
        let settings = try JSONDecoder().decode(GenerationSettings.self, from: Data(json.utf8))
        #expect(settings.referenceOrigin == nil)
        #expect(settings.referenceStrength == 1)
        #expect(settings.frames == 1)
    }

    @Test("settings carrying an origin survive a round trip through JSON")
    func settingsRoundTrip() throws {
        var settings = GenerationSettings.defaults(for: Self.editing)
        settings.referenceImage = Self.picture
        settings.referenceOrigin = "harbour-1234.png"
        let coded = try JSONDecoder().decode(
            GenerationSettings.self, from: try JSONEncoder().encode(settings))
        #expect(coded.referenceOrigin == "harbour-1234.png")
    }

    @Test("clearing the picture clears the origin, and a drop overwrites a library one")
    func clearingClearsTheOrigin() async throws {
        let bed = EngineTestBed()
        let store = bed.store(descriptor: Self.editing)
        store.warmsUpAfterLoad = false
        await store.bootstrap()

        store.useAsReference(Self.picture, origin: "harbour-1234.png")
        #expect(store.settings.referenceOrigin == "harbour-1234.png")

        store.useAsReference(Self.picture)
        #expect(store.settings.referenceOrigin == nil, "a drop knows no file name")

        store.useAsReference(Self.picture, origin: "harbour-1234.png")
        store.useAsReference(nil)
        #expect(store.settings.referenceOrigin == nil)
        #expect(store.settings.referenceImage == nil)
    }

    @Test("a variation of an edit keeps the picture it started from and where it came from")
    func variationKeepsTheOrigin() async throws {
        let bed = EngineTestBed()
        let store = bed.store(descriptor: Self.editing)
        store.warmsUpAfterLoad = false
        await store.bootstrap()
        store.settings.prompt = "make it night"
        store.useAsReference(Self.picture, origin: "harbour-1234.png")
        store.generate()
        while store.isRunning { await store.settle() }

        let made = try #require(store.history.first)
        #expect(made.settings.referenceOrigin == "harbour-1234.png")
        store.useAsReference(nil)
        store.select(made)
        #expect(store.settings.referenceOrigin == "harbour-1234.png")
    }

    @Test("a model that cannot read a picture is clamped free of the origin too")
    func clampDropsTheOrigin() {
        var settings = GenerationSettings.defaults(for: Self.editing)
        settings.referenceImage = Self.picture
        settings.referenceOrigin = "harbour-1234.png"
        let clamped = ReferenceOriginTests.plain.capabilities.clamp(settings)
        #expect(clamped.referenceImage == nil)
        #expect(clamped.referenceOrigin == nil)
    }

    /// A model with no way to read a picture at all, built rather than borrowed: every model
    /// the catalog ships can take one.
    static let plain: ModelDescriptor = {
        let base = ModelCatalog.zImageTurbo4bit
        let capabilities = ModelCapabilities(
            sizeAlignment: base.capabilities.sizeAlignment,
            sizePresets: base.capabilities.sizePresets,
            sizeBounds: base.capabilities.sizeBounds,
            defaultSize: base.capabilities.defaultSize,
            stepBounds: base.capabilities.stepBounds,
            defaultSteps: base.capabilities.defaultSteps,
            guidanceBounds: base.capabilities.guidanceBounds,
            defaultGuidance: base.capabilities.defaultGuidance,
            supportsNegativePrompt: base.capabilities.supportsNegativePrompt,
            supportsSeed: base.capabilities.supportsSeed,
            supportsReferenceImage: false
        )
        return ModelDescriptor(
            id: "text-to-image-only",
            displayName: "Text to image only",
            variantName: nil,
            backend: base.backend,
            source: base.source,
            quantization: base.quantization,
            downloadBytes: base.downloadBytes,
            residentBytes: base.residentBytes,
            peakBytes: base.peakBytes,
            tiledPeakBytes: base.tiledPeakBytes,
            maxPromptTokens: base.maxPromptTokens,
            capabilities: capabilities
        )
    }()

    private static func image(origin: String?) -> GeneratedImage {
        var settings = GenerationSettings.defaults(for: editing)
        settings.prompt = "a lighthouse"
        settings.seed = 99
        settings.referenceImage = picture
        settings.referenceStrength = 0.6
        settings.referenceOrigin = origin
        return GeneratedImage(
            pngData: MockBackend.pngData, settings: settings, modelID: editing.id,
            duration: .seconds(2))
    }
}
