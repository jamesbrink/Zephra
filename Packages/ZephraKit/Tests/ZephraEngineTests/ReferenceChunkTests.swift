import Foundation
import Testing
import ZephraCore

@testable import ZephraEngine

/// Several reference pictures inside one PNG, filed under numbered keywords.
@Suite("The pictures an edit started from, in the file that came out of it")
struct ReferenceChunkTests {
    private static func picture(_ byte: UInt8, origin: String?) -> ReferencePicture {
        ReferencePicture(
            data: Data([0x89, 0x50, 0x4E, 0x47] + Array(repeating: byte, count: 8 + Int(byte))),
            origin: origin)
    }

    private static func image(_ pictures: [ReferencePicture]) -> GeneratedImage {
        var settings = GenerationSettings.defaults(for: ModelCatalog.default)
        settings.prompt = "a lighthouse"
        settings.seed = 99
        settings.referenceImages = pictures
        settings.referenceStrength = 0.6
        return GeneratedImage(
            pngData: MockBackend.pngData, settings: settings, modelID: ModelCatalog.default.id,
            duration: .seconds(2))
    }

    private static var three: [ReferencePicture] {
        [picture(1, origin: "one.png"), picture(2, origin: nil), picture(3, origin: "three.png")]
    }

    @Test("three pictures go in and come back in the order they were read in")
    func threeRoundTrip() throws {
        let data = try GenerationRecord.embedded(in: Self.image(Self.three))
        let record = try #require(GenerationRecord.read(from: data))

        #expect(record.version == GenerationRecord.currentVersion, "still version 1")
        #expect(record.referenceByteCounts == Self.three.map(\.data.count))
        #expect(record.referenceOrigins.map { $0 } == ["one.png", nil, "three.png"])
        #expect(record.referenceBytes == Self.three[0].data.count, "the first, as it always was")
        #expect(record.referenceOrigin == "one.png")

        let read = GenerationRecord.references(in: data)
        #expect(read == Self.three)
        #expect(record.image(pngData: data, fileURL: nil, referenceImages: read)
            .settings.referenceImages == Self.three)
    }

    @Test("the numbered keywords start at two, so picture one is where it always was")
    func theKeywordsAreNumberedFromTwo() throws {
        #expect(GenerationRecord.referenceKeyword(at: 0) == "zephra:reference")
        #expect(GenerationRecord.referenceKeyword(at: 1) == "zephra:reference.2")
        #expect(GenerationRecord.allReferenceKeywords.count == ReferenceLimits.maximumPictures)
        #expect(GenerationRecord.allReferenceKeywords.last == "zephra:reference.10")

        let text = try PNGTextChunks.read(
            from: try GenerationRecord.embedded(in: Self.image(Self.three)))
        #expect(text["zephra:reference"] != nil)
        #expect(text["zephra:reference.2"] != nil)
        #expect(text["zephra:reference.3"] != nil)
        #expect(text["zephra:reference.4"] == nil)
    }

    @Test("a one-picture edit writes the file it always wrote")
    func onePictureIsUnchanged() throws {
        let one = Self.picture(1, origin: "one.png")
        let data = try GenerationRecord.embedded(in: Self.image([one]))
        let text = try PNGTextChunks.read(from: data)

        #expect(
            Set(text.keys)
                == ["zephra:generation", "Software", "Description", "zephra:reference"],
            "one chunk, under the keyword every build before this one reads")
        let json = try #require(text["zephra:generation"])
        #expect(!json.contains("referenceByteCounts"), "and nothing new in the record")
        #expect(!json.contains("referenceOrigins"))
        #expect(GenerationRecord.reference(in: data) == one.data)
    }

    @Test("a build that reads only the first picture still gets it, and its length still checks")
    func theOldReaderStillWorks() throws {
        let data = try GenerationRecord.embedded(in: Self.image(Self.three))
        #expect(GenerationRecord.reference(in: data) == Self.three[0].data)
    }

    @Test("a chunk another tool rewrote ends the strip rather than poisoning it")
    func arewrittenChunkStopsTheRead() throws {
        let data = try GenerationRecord.embedded(in: Self.image(Self.three))
        let rewritten = try PNGTextChunks.replacing(
            [(keyword: "zephra:reference.3", text: Data([0xFF, 0xFE]).base64EncodedString())],
            in: data)

        let read = GenerationRecord.references(in: rewritten)
        #expect(read.count == 2, "two pictures are better than a third in somebody else's place")
        #expect(read == Array(Self.three.prefix(2)))
    }

    @Test("origins shorter than the counts pad with nothing rather than shifting")
    func shortOriginsPad() throws {
        var record = GenerationRecord(Self.image(Self.three))
        record.referenceOrigins = ["one.png"]
        let data = try GenerationRecord.embedded(
            record, in: MockBackend.pngData, prompt: record.prompt,
            referenceTexts: Self.three.map { $0.data.base64EncodedString() })

        let read = GenerationRecord.references(in: data)
        #expect(read.map(\.origin) == ["one.png", nil, nil])
    }

    @Test("a file written before the counts existed reads its one picture from referenceBytes")
    func olderFilesReadAsOnePicture() throws {
        let one = Self.picture(1, origin: "one.png")
        var record = GenerationRecord(Self.image([one]))
        record.referenceByteCounts = nil
        record.referenceOrigins = nil
        let data = try GenerationRecord.embedded(
            record, in: MockBackend.pngData, prompt: record.prompt,
            referenceTexts: [one.data.base64EncodedString()])

        #expect(GenerationRecord.references(in: data) == [one])
    }

    @MainActor
    @Test("a continued clip's poster carries none of the ten keywords")
    func theStitchedPosterIsBare() throws {
        let data = try GenerationRecord.embedded(in: Self.image(Self.three))
        let bare = try GenerationStore.bare(poster: data)
        let text = try PNGTextChunks.read(from: bare)
        for keyword in GenerationRecord.allReferenceKeywords {
            #expect(text[keyword] == nil, "\(keyword) is still on the poster")
        }
        #expect(text[GenerationRecord.keyword] == nil)
    }
}
