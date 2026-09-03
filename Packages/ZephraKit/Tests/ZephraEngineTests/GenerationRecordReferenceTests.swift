import Foundation
import Testing
import ZephraCore

@testable import ZephraEngine

@Suite("GenerationRecord, reference provenance")
struct GenerationRecordReferenceTests {
    /// A second PNG, distinguishable from the image's own bytes, standing in for the picture an
    /// edit started from.
    private static let picture = Data([0x89, 0x50, 0x4E, 0x47] + Array(repeating: 0x2A, count: 40))

    @Test("a generation with no reference records no strength, and reads back none")
    func noReference() throws {
        let data = try GenerationRecord.embedded(in: Self.image())
        let record = try #require(GenerationRecord.read(from: data))
        #expect(record.referenceBytes == nil)
        #expect(record.referenceStrength == nil, "no picture, so no distance from one")
        #expect(GenerationRecord.reference(in: data) == nil)
        #expect(record.image(pngData: data, fileURL: nil).settings.referenceImage == nil)
        #expect(
            record.image(pngData: data, fileURL: nil).settings.referenceStrength == 1,
            "the value that changes nothing")
    }

    @Test("an edit records its picture's size and the strength it ran at")
    func referenceRoundTrip() throws {
        let image = Self.image(reference: Self.picture, strength: 0.45)
        let data = try GenerationRecord.embedded(in: image)
        let record = try #require(GenerationRecord.read(from: data))

        #expect(record.version == GenerationRecord.currentVersion, "still version 1")
        #expect(record.referenceBytes == Self.picture.count)
        #expect(record.referenceStrength == 0.45)

        let recovered = try #require(GenerationRecord.reference(in: data))
        #expect(recovered == Self.picture, "the picture itself, out of its own chunk")

        let restored = record.image(pngData: data, fileURL: nil, referenceImage: recovered)
        #expect(restored.settings.referenceImage == Self.picture)
        #expect(restored.settings.referenceStrength == 0.45, "a variation repeats the same edit")
    }

    @Test("a record read without its picture still says what the strength was")
    func strengthSurvivesWithoutThePicture() throws {
        let data = try GenerationRecord.embedded(
            in: Self.image(reference: Self.picture, strength: 0.7))
        let record = try #require(GenerationRecord.read(from: data))

        // `image(pngData:fileURL:)` with no reference passed: the caller did not read the
        // second chunk, or it did not survive. The strength is still the record's to report.
        let restored = record.image(pngData: data, fileURL: nil)
        #expect(restored.settings.referenceImage == nil)
        #expect(restored.settings.referenceStrength == 0.7)
        #expect(record.referenceBytes == Self.picture.count, "and the provenance still stands")
    }

    @Test("a model that conditions on the picture directly records a strength of one")
    func directConditioningRecordsANeutralStrength() throws {
        // What klein writes: `clamp` pins the strength at 1, so the record says the edit had no
        // distance to travel rather than implying a partial start that never happened.
        let clamped = ModelCatalog.flux2Klein4bit.capabilities.clamp(
            Self.settings(reference: Self.picture, strength: 0.3))
        let image = GeneratedImage(
            pngData: MockBackend.pngData, settings: clamped,
            modelID: ModelCatalog.flux2Klein4bit.id, duration: .seconds(2))

        let record = GenerationRecord(image)
        #expect(record.referenceBytes == Self.picture.count)
        #expect(record.referenceStrength == 1)
    }

    private static func settings(reference: Data?, strength: Double) -> GenerationSettings {
        var settings = GenerationSettings.defaults(for: ModelCatalog.default)
        settings.prompt = "a lighthouse"
        settings.seed = 99
        settings.referenceImage = reference
        settings.referenceStrength = strength
        return settings
    }

    private static func image(reference: Data? = nil, strength: Double = 1) -> GeneratedImage {
        GeneratedImage(
            pngData: MockBackend.pngData,
            settings: settings(reference: reference, strength: strength),
            modelID: ModelCatalog.default.id,
            duration: .seconds(2)
        )
    }
}
