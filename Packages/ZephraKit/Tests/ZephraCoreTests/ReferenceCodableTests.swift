import Foundation
import Testing

@testable import ZephraCore

/// What a settings value's reference pictures look like on disk and on the wire.
///
/// The golden string is the whole point of the suite: a one-picture request must encode to the
/// bytes it encoded to before the list existed, or every multi-host receipt already written
/// names work whose digest no longer matches it.
@Suite("Settings carrying reference pictures, written and read")
struct ReferenceCodableTests {
    private static let picture = Data([0x89, 0x50, 0x4E, 0x47])

    private static var settings: GenerationSettings {
        GenerationSettings(
            prompt: "a lighthouse", size: ImageSize(width: 64, height: 64), steps: 4,
            guidance: 0, seed: 42, referenceImage: picture, referenceStrength: 0.6,
            referenceOrigin: "harbour.png")
    }

    private static func encoded(_ settings: GenerationSettings) throws -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return String(decoding: try encoder.encode(settings), as: UTF8.self)
    }

    @Test("a one-picture value encodes the bytes it always did")
    func onePictureIsUnchanged() throws {
        let golden = """
            {"frames":1,"guidance":0,"prompt":"a lighthouse","referenceImage":"iVBORw==",\
            "referenceOrigin":"harbour.png","referenceStrength":0.6,"seed":42,\
            "size":{"height":64,"width":64},"steps":4}
            """
        #expect(try Self.encoded(Self.settings) == golden)
    }

    @Test("several pictures round-trip in order, and the first is still written on its own")
    func severalRoundTrip() throws {
        var settings = Self.settings
        settings.referenceImages = [
            ReferencePicture(data: Data([1]), origin: "one.png"),
            ReferencePicture(data: Data([2]), size: ImageSize(width: 8, height: 4)),
            ReferencePicture(data: Data([3]), origin: "three.png"),
        ]
        let json = try Self.encoded(settings)
        #expect(json.contains("\"referenceImages\""), "the list is written")
        #expect(json.contains("\"referenceOrigin\":\"one.png\""), "and so is the first alone")

        let coded = try JSONDecoder().decode(
            GenerationSettings.self, from: Data(json.utf8))
        #expect(coded.referenceImages == settings.referenceImages)
        #expect(coded.referenceImage == Data([1]))
        #expect(coded.referenceOrigin == "one.png")
    }

    @Test("JSON from an older build decodes into one picture with its origin")
    func olderPayloadDecodes() throws {
        let json = """
            {"prompt":"a lighthouse","size":{"width":64,"height":64},"steps":4,"guidance":0,
             "seed":42,"referenceImage":"iVBORw==","referenceOrigin":"harbour.png",
             "referenceStrength":0.6}
            """
        let coded = try JSONDecoder().decode(GenerationSettings.self, from: Data(json.utf8))
        #expect(coded.referenceImages.count == 1)
        #expect(coded.referenceImage == Self.picture)
        #expect(coded.referenceOrigin == "harbour.png")
    }

    @Test("a picture whose bytes were stripped for the wire comes back saying what it was of")
    func strippedPictureKeepsItsOrigin() throws {
        let json = """
            {"prompt":"a lighthouse","size":{"width":64,"height":64},"steps":4,"guidance":0,
             "seed":42,"referenceOrigin":"harbour.png","referenceStrength":0.6,"frames":1}
            """
        let coded = try JSONDecoder().decode(GenerationSettings.self, from: Data(json.utf8))
        #expect(coded.referenceImages.count == 1)
        #expect(coded.referenceImage == nil, "there are no bytes to read")
        #expect(coded.referenceOrigin == "harbour.png")
    }

    @Test("a payload with both shapes prefers the list")
    func theListWins() throws {
        var settings = Self.settings
        settings.referenceImages = [
            ReferencePicture(data: Data([7]), origin: "seven.png"),
            ReferencePicture(data: Data([8]), origin: "eight.png"),
        ]
        let coded = try JSONDecoder().decode(
            GenerationSettings.self, from: Data(try Self.encoded(settings).utf8))
        #expect(coded.referenceImages.count == 2)
        #expect(coded.referenceImage == Data([7]))
    }
}
