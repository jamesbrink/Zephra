import Foundation
import Testing
import ZephraCore

@testable import ZephraEngine

@Suite("GenerationRecord")
struct GenerationRecordTests {
    @Test("a record survives the trip through a PNG intact")
    func roundTrip() throws {
        let settings = GenerationSettings(
            prompt: "a lighthouse at dusk — fog rolling in",
            negativePrompt: "blurry",
            size: ImageSize(width: 768, height: 512),
            steps: 7,
            guidance: 3.5,
            seed: .max
        )
        let image = GeneratedImage(
            pngData: MockBackend.pngData,
            settings: settings,
            modelID: "mzbac/Z-Image-Turbo-8bit",
            createdAt: Date(timeIntervalSince1970: 1_772_000_000),
            duration: .seconds(19) + .milliseconds(400)
        )

        let data = try GenerationRecord.embedded(in: image)
        let record = try #require(GenerationRecord.read(from: data))
        let restored = record.image(pngData: data, fileURL: nil)

        #expect(record.version == GenerationRecord.currentVersion)
        #expect(restored.settings == settings, "the whole settings value, seed included")
        #expect(restored.modelID == "mzbac/Z-Image-Turbo-8bit")
        #expect(restored.createdAt == image.createdAt)
        #expect(restored.duration == .seconds(19.4))
        #expect(restored.id != image.id, "identity belongs to the session, not the file")
    }

    @Test("the record sits alongside a Software line and a readable Description")
    func standardChunks() throws {
        let data = try GenerationRecord.embedded(in: Self.image(prompt: "a harbour in the rain"))
        let text = try PNGTextChunks.read(from: data)

        #expect(text["Description"] == "a harbour in the rain")
        #expect(text["Software"]?.hasPrefix("Zephra") == true)
        #expect(text[GenerationRecord.keyword]?.contains(#""seed":99"#) == true)
        // Sorted keys, so the same image always writes the same bytes.
        #expect(text[GenerationRecord.keyword]?.hasPrefix(#"{"createdAt""#) == true)
        #expect(text[GenerationRecord.referenceKeyword] == nil, "a plain generation files no reference")
    }

    @Test("an edited image carries its reference beside the record, and the record says how large it was")
    func referenceRoundTrip() throws {
        let reference = Data((0..<300).map { UInt8($0 % 251) })
        var settings = Self.image(prompt: "the same harbour, at night").settings
        settings.referenceImage = reference
        let image = GeneratedImage(
            pngData: MockBackend.pngData, settings: settings, modelID: "flux2-klein-4b-4bit",
            createdAt: Date(timeIntervalSince1970: 1_772_000_000), duration: .seconds(6))

        let data = try GenerationRecord.embedded(in: image)
        let record = try #require(GenerationRecord.read(from: data))
        #expect(record.referenceBytes == 300)
        #expect(GenerationRecord.reference(in: data) == reference)
        let restored = record.image(
            pngData: data, fileURL: nil, referenceImage: GenerationRecord.reference(in: data))
        #expect(restored.settings == settings, "the reference comes back with the rest")
    }

    @Test("a record whose reference chunk was stripped, or rewritten to another length, reads as a plain generation")
    func damagedReferenceIsDropped() throws {
        var settings = Self.image(prompt: "a harbour").settings
        settings.referenceImage = Data(repeating: 7, count: 64)
        let image = GeneratedImage(
            pngData: MockBackend.pngData, settings: settings, modelID: "flux2-klein-4b-4bit",
            createdAt: Date(), duration: .seconds(1))
        let data = try GenerationRecord.embedded(in: image)

        // Keep the record, replace the reference with one of another length.
        let record = try #require(PNGTextChunks.read(from: data)[GenerationRecord.keyword])
        let rewritten = try PNGTextChunks.inserting(
            [
                (keyword: GenerationRecord.keyword, text: record),
                (keyword: GenerationRecord.referenceKeyword,
                 text: Data(repeating: 7, count: 32).base64EncodedString()),
            ],
            into: MockBackend.pngData)
        #expect(GenerationRecord.read(from: rewritten)?.referenceBytes == 64)
        #expect(GenerationRecord.reference(in: rewritten) == nil)

        let stripped = try PNGTextChunks.inserting(
            [(keyword: GenerationRecord.keyword, text: record)], into: MockBackend.pngData)
        #expect(GenerationRecord.reference(in: stripped) == nil)
    }

    @Test("embedding a record twice changes nothing the second time")
    func idempotent() throws {
        let image = Self.image(prompt: "a lighthouse")
        let once = try GenerationRecord.embedded(in: image)
        let twice = try GenerationRecord.embedded(in: image.withPNGData(once))
        #expect(once == twice)
    }

    @Test("a PNG with no record, and anything that is not a PNG, read as nothing")
    func missingRecord() {
        #expect(GenerationRecord.read(from: MockBackend.pngData) == nil)
        #expect(GenerationRecord.read(from: Data("not a picture".utf8)) == nil)
        #expect(GenerationRecord.read(from: Data()) == nil)
    }

    @Test("a record from a later version is left alone")
    func futureVersion() throws {
        var record = GenerationRecord(Self.image(prompt: "a lighthouse"))
        record.version = GenerationRecord.currentVersion + 1
        let data = try PNGTextChunks.inserting(
            [(keyword: GenerationRecord.keyword, text: try GenerationRecord.json(for: record))],
            into: MockBackend.pngData
        )
        #expect(GenerationRecord.read(from: data) == nil)
    }

    private static func image(prompt: String) -> GeneratedImage {
        var settings = GenerationSettings.defaults(for: ModelCatalog.default)
        settings.prompt = prompt
        settings.seed = 99
        return GeneratedImage(
            pngData: MockBackend.pngData,
            settings: settings,
            modelID: ModelCatalog.default.id,
            duration: .seconds(2)
        )
    }
}

extension GeneratedImage {
    /// The same record with different bytes, for tests that re-embed what a writer produced.
    fileprivate func withPNGData(_ data: Data) -> GeneratedImage {
        GeneratedImage(
            id: id,
            pngData: data,
            settings: settings,
            modelID: modelID,
            createdAt: createdAt,
            duration: duration,
            fileURL: fileURL
        )
    }
}
