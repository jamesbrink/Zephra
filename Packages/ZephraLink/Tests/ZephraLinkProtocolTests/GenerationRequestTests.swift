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
