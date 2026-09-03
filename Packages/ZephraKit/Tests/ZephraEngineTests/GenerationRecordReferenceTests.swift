import CryptoKit
import Foundation
import Testing
import ZephraCore

@testable import ZephraEngine

@Suite("GenerationRecord, reference provenance")
struct GenerationRecordReferenceTests {
    @Test("a generation with no reference writes no reference fields and reads back none")
    func noReference() throws {
        let data = try GenerationRecord.embedded(in: Self.image())
        let record = try #require(GenerationRecord.read(from: data))
        #expect(record.referenceFileName == nil)
        #expect(record.referenceDigest == nil)
        #expect(record.referenceStrength == nil)
        #expect(record.image(pngData: data, fileURL: nil).settings.reference == nil)
    }

    @Test("a reference is recorded by name, digest and strength, and found again by the file")
    func referenceRoundTrip() throws {
        let library = Self.scratchDirectory()
        defer { try? FileManager.default.removeItem(at: library) }
        let source = try Self.writeSource(named: "harbour.png", in: library)
        let reference = ReferenceImage(url: source, strength: 0.45)
        let digest = try reference.digest()

        let data = try GenerationRecord.embedded(
            in: Self.image(reference: reference), referenceDigest: digest
        )
        let record = try #require(GenerationRecord.read(from: data))

        #expect(record.version == GenerationRecord.currentVersion, "still version 1")
        #expect(record.referenceFileName == "harbour.png")
        #expect(record.referenceStrength == 0.45)
        #expect(record.referenceDigest?.count == 64, "SHA-256 as lowercase hex")
        let expected = SHA256.hash(data: MockBackend.pngData)
            .map { String(format: "%02x", $0) }.joined()
        #expect(record.referenceDigest == expected, "the source file's bytes, not the image's")

        let restored = record.image(
            pngData: data, fileURL: library.appending(path: "generated.png")
        )
        #expect(restored.settings.reference == reference)
    }

    @Test("a reference is found from a sub-folder in the library's own Sources folder")
    func referenceResolvesFromASubfolder() throws {
        let library = Self.scratchDirectory()
        defer { try? FileManager.default.removeItem(at: library) }
        let source = try Self.writeSource(named: "harbour.png", in: library)
        let deleted = library.appending(path: "Recently Deleted", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: deleted, withIntermediateDirectories: true)

        var record = GenerationRecord(Self.image())
        record.referenceFileName = "harbour.png"
        record.referenceStrength = 0.7

        let found = record.reference(nextTo: deleted.appending(path: "old.png"))
        #expect(found == ReferenceImage(url: source, strength: 0.7))
    }

    @Test("a reference whose file has gone comes back as no reference, provenance intact")
    func missingReferenceFileIsDropped() {
        let library = Self.scratchDirectory()
        var record = GenerationRecord(Self.image())
        record.referenceFileName = "harbour.png"
        record.referenceDigest = String(repeating: "a", count: 64)
        record.referenceStrength = 0.5

        #expect(record.reference(nextTo: library.appending(path: "generated.png")) == nil)
        #expect(record.referenceFileName == "harbour.png", "the record still says what it was")
    }

    private static func image(reference: ReferenceImage? = nil) -> GeneratedImage {
        var settings = GenerationSettings.defaults(for: ModelCatalog.default)
        settings.prompt = "a lighthouse"
        settings.seed = 99
        settings.reference = reference
        return GeneratedImage(
            pngData: MockBackend.pngData,
            settings: settings,
            modelID: ModelCatalog.default.id,
            duration: .seconds(2)
        )
    }

    /// A file in the library's `Sources/` folder, with bytes worth hashing.
    private static func writeSource(named name: String, in library: URL) throws -> URL {
        let sources = library.appending(
            path: GenerationRecord.sourcesFolderName, directoryHint: .isDirectory
        )
        try FileManager.default.createDirectory(at: sources, withIntermediateDirectories: true)
        let url = sources.appending(path: name)
        try MockBackend.pngData.write(to: url)
        return url
    }

    private static func scratchDirectory() -> URL {
        URL(filePath: NSTemporaryDirectory())
            .appending(path: "ZephraReferenceTests-\(UUID().uuidString)", directoryHint: .isDirectory)
    }
}
