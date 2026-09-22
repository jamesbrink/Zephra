import Foundation
import Testing
import UIKit
import ZephraCore
import ZephraLinkClient
import ZephraLinkProtocol
import ZephraTestSupport

@testable import ZephraMobile

/// "Use as Reference", from the library's menu to the picture in the capsule's well.
///
/// The library says a file **name** and nothing else, and the canvas is what turns that into
/// bytes. What these pin is the whole of that path: the request is taken once, the picture
/// comes out of the phone's own cache rather than over the link a second time, and what lands
/// in the well names the file it came from — which is what the Mac records beside the run.
@MainActor
@Suite("The library's picture reaches the capsule's well")
struct ReferenceIntentTests {
    @Test("The name becomes the picture in the well, naming the file it came from")
    func theRequestFillsTheWell() async throws {
        let bed = try await Bed()
        bed.intent.use(bed.name)

        await bed.take()

        #expect(bed.draft.reference != nil, "the well is filled")
        #expect(bed.draft.referenceOrigin == bed.name)
        #expect(bed.intent.fileName == nil, "and the request is spent")
    }

    @Test("The picture comes out of the cache, over a client whose blobs never answer")
    func thePictureCrossesTheLinkOnce() async throws {
        let bed = try await Bed()
        // A frozen client fails every blob, so anything that reached for the Mac would come
        // back with nothing. The bytes are on the phone because the library already fetched
        // them, which is the whole point of one cache for both surfaces.
        bed.catalog.attach(
            LinkClient.frozen(
                snapshot: try #require(MobilePreview.snapshot()), library: MobilePreview.library()))
        bed.intent.use(bed.name)

        await bed.take()

        #expect(bed.draft.reference != nil)
    }

    @Test("It is acted on once: a second reader gets nothing")
    func theRequestIsTakenOnce() async throws {
        let bed = try await Bed()
        bed.intent.use(bed.name)
        await bed.take()
        bed.draft.clearReference()

        await bed.take()

        #expect(
            bed.draft.reference == nil,
            "a spent request does not refill a well somebody emptied")
    }

    @Test("A picture this phone has never fetched, with no Mac in reach, leaves the well alone")
    func nothingToFetchChangesNothing() async throws {
        let bed = try await Bed()
        bed.intent.use("never-seen.png")

        await bed.take()

        #expect(bed.draft.reference == nil)
        #expect(bed.draft.referenceOrigin == nil)
    }

    @Test("On a model that makes clips the size follows the picture, as it does on the Mac")
    func theSizeFollowsThePicture() async throws {
        let bed = try await Bed(capabilities: Bed.clipCapabilities)
        bed.intent.use(bed.name)

        await bed.take()

        let size = bed.draft.settings.size
        #expect(size.width > size.height, "the picture is wider than it is tall")
    }

    /// A catalog over a scratch directory with one picture already in its file store, which is
    /// a phone that has looked at that picture in the library, plus the two objects the canvas
    /// puts between the library and the well.
    struct Bed {
        let scratch: Scratch
        let catalog: LibraryCatalog
        let intent = ReferenceIntent()
        let draft = PromptDraft()

        /// The picture in the store, under the name the Mac's library would know it by.
        static let name = "zephra-0001.png"
        var name: String { Self.name }

        private let capabilities: CapabilitiesSummary

        init(capabilities: CapabilitiesSummary = Bed.pictureCapabilities) async throws {
            let scratch = Scratch("ReferenceIntent")
            let catalog = LibraryCatalog(
                libraryRoot: scratch.url("Library"), filesRoot: scratch.url("Files"))
            await catalog.fileStore.store(
                Self.picture(width: 1200, height: 800), as: Self.name)
            self.scratch = scratch
            self.catalog = catalog
            self.capabilities = capabilities
        }

        /// What the canvas does when the intent changes: `ReferenceIntentReader` is three lines
        /// of SwiftUI over exactly this.
        func take() async {
            await ReferenceAdoption.take(intent, from: catalog) { picture, origin in
                draft.adopt(picture, origin: origin, fitting: capabilities.capabilities)
                return true
            }
        }

        /// A picture of a given shape, drawn rather than read, so the suite carries no fixture.
        static func picture(width: Int, height: Int) -> Data {
            let size = CGSize(width: width, height: height)
            let format = UIGraphicsImageRendererFormat()
            format.scale = 1
            return UIGraphicsImageRenderer(size: size, format: format).image { context in
                UIColor.systemTeal.setFill()
                context.fill(CGRect(origin: .zero, size: size))
            }.pngData() ?? Data()
        }

        /// A model that makes pictures and reads a reference: the size stays where it is.
        static let pictureCapabilities = CapabilitiesSummary(
            ModelCapabilities(
                sizeAlignment: 64, sizePresets: [ImageSize(width: 1024, height: 1024)],
                sizeBounds: 256...2048, defaultSize: ImageSize(width: 1024, height: 1024),
                stepBounds: 1...20, defaultSteps: 9, guidanceBounds: 0...0, defaultGuidance: 0,
                supportsNegativePrompt: false, supportsSeed: true, supportsReferenceImage: true,
                referenceStrengthBounds: 0.1...0.9, defaultReferenceStrength: 0.6))

        /// A model that makes clips: the frame takes the picture's own shape.
        static let clipCapabilities = CapabilitiesSummary(
            ModelCapabilities(
                sizeAlignment: 32, sizePresets: [ImageSize(width: 704, height: 704)],
                sizeBounds: 256...1280, defaultSize: ImageSize(width: 704, height: 704),
                stepBounds: 3...3, defaultSteps: 3, guidanceBounds: 0...0, defaultGuidance: 0,
                supportsNegativePrompt: false, supportsSeed: true, supportsReferenceImage: true,
                frameBounds: 5...121, defaultFrames: 49, frameAlignment: 4))
    }
}
