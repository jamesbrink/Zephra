import CoreGraphics
import Foundation
import ImageIO
import Testing
import UniformTypeIdentifiers
import ZephraCore

@testable import Zephra

/// What the well says under itself about a cut-out handed to a model that reads no transparency.
///
/// The picture's own PNG header answers whether it is transparent, so these build two real PNGs
/// — one with an alpha channel, one without — rather than asserting over a flag somebody set.
@Suite("The white-matte note under the well")
struct ReferenceMatteNoteTests {
    private func capabilities(pictures: Bool = true, readsAlpha: Bool = false)
        -> ModelCapabilities
    {
        ModelCapabilities(
            sizeAlignment: 16,
            sizePresets: [ImageSize(width: 1024, height: 1024)],
            sizeBounds: 512...1536,
            defaultSize: ImageSize(width: 1024, height: 1024),
            stepBounds: 1...8,
            defaultSteps: 4,
            guidanceBounds: 0...0,
            defaultGuidance: 0,
            supportsNegativePrompt: false,
            supportsSeed: true,
            supportsReferenceImage: pictures,
            referenceImageCount: 1...10,
            readsTransparentReferences: readsAlpha)
    }

    /// A one-pixel PNG, with an alpha channel or without one.
    private func png(alpha: Bool) throws -> Data {
        let info: CGImageAlphaInfo = alpha ? .premultipliedLast : .noneSkipLast
        let context = try #require(
            CGContext(
                data: nil, width: 4, height: 4, bitsPerComponent: 8, bytesPerRow: 0,
                space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: info.rawValue))
        context.setFillColor(CGColor(red: 0.5, green: 0.2, blue: 0.1, alpha: alpha ? 0.5 : 1))
        context.fill(CGRect(x: 0, y: 0, width: 4, height: 4))
        let image = try #require(context.makeImage())
        let output = NSMutableData()
        let destination = try #require(
            CGImageDestinationCreateWithData(
                output, UTType.png.identifier as CFString, 1, nil))
        CGImageDestinationAddImage(destination, image, nil)
        #expect(CGImageDestinationFinalize(destination))
        return output as Data
    }

    private func picture(alpha: Bool) throws -> ReferencePicture {
        ReferencePicture(data: try png(alpha: alpha))
    }

    @Test("a transparent picture on a model that mattes it names the model")
    func aTransparentPictureIsNamed() throws {
        let note = ReferenceMatteNote.text(
            for: [try picture(alpha: true)], capabilities: capabilities(),
            modelName: "Qwen-Image 2.1")
        #expect(note == "Read over white by Qwen-Image 2.1.")
    }

    @Test("one transparent picture among opaque ones is enough to say so")
    func oneTransparentPictureIsEnough() throws {
        let pictures = [try picture(alpha: false), try picture(alpha: true)]
        #expect(
            ReferenceMatteNote.text(
                for: pictures, capabilities: capabilities(), modelName: "klein 4-bit") != nil)
    }

    @Test("opaque pictures say nothing")
    func opaquePicturesSayNothing() throws {
        #expect(
            ReferenceMatteNote.text(
                for: [try picture(alpha: false)], capabilities: capabilities(),
                modelName: "klein 4-bit") == nil)
    }

    @Test("an empty well says nothing")
    func anEmptyWellSaysNothing() {
        #expect(
            ReferenceMatteNote.text(for: [], capabilities: capabilities(), modelName: "klein")
                == nil)
    }

    @Test("a model that reads the transparency itself says nothing")
    func aModelThatReadsAlphaSaysNothing() throws {
        #expect(
            ReferenceMatteNote.text(
                for: [try picture(alpha: true)], capabilities: capabilities(readsAlpha: true),
                modelName: "Qwen-Image 2.1") == nil)
    }

    @Test("a model that reads no picture at all says nothing")
    func aModelWithNoWellSaysNothing() throws {
        #expect(
            ReferenceMatteNote.text(
                for: [try picture(alpha: true)], capabilities: capabilities(pictures: false),
                modelName: "Z-Image Turbo") == nil)
    }

    @Test("bytes that are not a picture are not called transparent")
    func nonsenseIsNotTransparent() {
        let rubbish = ReferencePicture(data: Data([0, 1, 2, 3]))
        #expect(!ReferenceMatteNote.isTransparent(rubbish))
        #expect(!ReferenceMatteNote.isTransparent(ReferencePicture(data: Data())))
    }

    @Test("the sentence itself is the role's, and every role says it the same way")
    func theSentenceIsTheRoles() {
        for role in [
            ReferenceRole.reference, .startFrom, .firstFrame, .continues,
        ] {
            #expect(role.whiteMatteNote(modelName: "klein 4-bit") == "Read over white by klein 4-bit.")
        }
    }
}
