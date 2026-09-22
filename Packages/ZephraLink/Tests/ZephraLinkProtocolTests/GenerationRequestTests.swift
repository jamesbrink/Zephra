import Foundation
import Testing
import ZephraCore
@testable import ZephraLinkProtocol

@Suite("A request from the phone never carries a picture inside it")
struct GenerationRequestTests {
    /// Settings with a reference picture in them, as the phone would hold them locally.
    static var withPicture: GenerationSettings {
        var settings = LinkFixtures.settings
        settings.referenceImage = Data(repeating: 0x89, count: 4096)
        settings.referenceStrength = 0.6
        return settings
    }

    @Test("The picture is dropped when the request is made")
    func pictureIsDroppedOnTheWayIn() {
        let request = GenerationRequest(
            modelID: "z-image-turbo-4bit", count: 1, settings: Self.withPicture,
            referenceBlobID: UUID())
        #expect(request.settings.referenceImage == nil)
        #expect(request.settings.referenceStrength == 0.6)
    }

    @Test("A picture smuggled in by a peer is dropped on the way out of the decoder")
    func pictureIsDroppedOnTheWayOut() throws {
        let hostile = """
            {"count":1,"modelID":"z-image-turbo-4bit","settings":\
            {"guidance":0,"prompt":"x","seed":1,"size":{"height":64,"width":64},"steps":1,\
            "referenceImage":"iVBORw0KGgo=","frames":1,"referenceStrength":1}}
            """
        let request = try LinkJSON.decode(GenerationRequest.self, from: Data(hostile.utf8))
        #expect(request.settings.referenceImage == nil)
    }

    @Test("The picture is named by its blob, which is how it actually crosses")
    func blobNamesThePicture() throws {
        let blob = UUID()
        let request = GenerationRequest(
            modelID: "z-image-turbo-4bit", count: 1, settings: Self.withPicture,
            referenceBlobID: blob)
        #expect(try LinkFixtures.roundTrip(request).referenceBlobID == blob)
    }

    @Test("A request carries its own id, so the Mac can tell a repeat from a second press")
    func theRequestKeepsItsOwnID() throws {
        let request = GenerationRequest(
            modelID: "z-image-turbo-4bit", count: 1, settings: LinkFixtures.settings)
        #expect(try LinkFixtures.roundTrip(request).requestID == request.requestID)
    }

    @Test("A request from a build that sent no id is still read, and is simply not recognisable")
    func anOlderRequestStillDecodes() throws {
        let older = """
            {"count":1,"modelID":"z-image-turbo-4bit","settings":\
            {"guidance":0,"prompt":"x","seed":1,"size":{"height":64,"width":64},"steps":1,\
            "frames":1,"referenceStrength":1}}
            """
        let first = try LinkJSON.decode(GenerationRequest.self, from: Data(older.utf8))
        let second = try LinkJSON.decode(GenerationRequest.self, from: Data(older.utf8))
        #expect(first.requestID != second.requestID, "two presses, since neither says otherwise")
    }

    @Test("Three pictures cross as three blobs, named in the order the model reads them")
    func severalBlobsCross() throws {
        let blobs = [UUID(), UUID(), UUID()]
        let request = GenerationRequest(
            modelID: "z-image-turbo-4bit", count: 1, settings: Self.withPicture,
            referenceBlobIDs: blobs)
        let read = try LinkFixtures.roundTrip(request)
        #expect(read.referenceBlobIDs == blobs)
        #expect(read.referenceBlobID == blobs[0], "the first is what a one-picture Mac reads")
    }

    @Test("An older build's single blob id decodes as a one-element list")
    func anOlderBuildsSingleIDIsOnePicture() throws {
        let blob = UUID()
        let older = """
            {"count":1,"modelID":"z-image-turbo-4bit","referenceBlobID":"\(blob.uuidString)",\
            "settings":{"guidance":0,"prompt":"x","seed":1,"size":{"height":64,"width":64},\
            "steps":1,"frames":1,"referenceStrength":1}}
            """
        let request = try LinkJSON.decode(GenerationRequest.self, from: Data(older.utf8))
        #expect(request.referenceBlobIDs == [blob])
    }

    @Test("A one-picture request encodes the bytes it always did")
    func onePictureIsByteIdentical() throws {
        let blob = UUID(uuidString: "11111111-2222-3333-4444-555555555555")!
        let id = UUID(uuidString: "66666666-7777-8888-9999-000000000000")!
        let request = GenerationRequest(
            modelID: "z-image-turbo-4bit", count: 1, settings: LinkFixtures.settings,
            referenceBlobID: blob, requestID: id)
        let json = String(decoding: try LinkJSON.encode(request), as: UTF8.self)
        #expect(!json.contains("referenceBlobIDs"), "no new key on a one-picture request")
        #expect(json.contains("\"referenceBlobID\":\"\(blob.uuidString)\""))
    }

    @Test("A count outside the bounds is clamped rather than refused", arguments: [
        (0, 1), (1, 1), (8, 8), (99, 8), (-3, 1),
    ])
    func countIsClamped(asked: Int, expected: Int) throws {
        let request = GenerationRequest(
            modelID: "z-image-turbo-4bit", count: asked, settings: LinkFixtures.settings)
        #expect(request.count == expected)
        #expect(try LinkFixtures.roundTrip(request).count == expected)
    }
}
