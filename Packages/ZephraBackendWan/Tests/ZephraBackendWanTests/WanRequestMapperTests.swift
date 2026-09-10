import CoreGraphics
import Foundation
import ImageIO
import Testing
import UniformTypeIdentifiers
import ZephraCore

@testable import ZephraBackendWan

@Suite("what the engine's settings become on their way into the pipeline")
struct WanRequestMapperTests {
    static let descriptor = ModelCatalog.wan22TI2V5B4bit

    /// A one-pixel PNG, which is all the mapper's decode needs to succeed.
    static func png() throws -> Data {
        let context = try #require(
            CGContext(
                data: nil, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue))
        context.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: 1, height: 1))
        let image = try #require(context.makeImage())
        let data = NSMutableData()
        let destination = try #require(
            CGImageDestinationCreateWithData(data, UTType.png.identifier as CFString, 1, nil))
        CGImageDestinationAddImage(destination, image, nil)
        #expect(CGImageDestinationFinalize(destination))
        return data as Data
    }

    static func settings(reference: Data?) -> GenerationSettings {
        var settings = GenerationSettings.defaults(for: descriptor)
        settings.referenceImage = reference
        return settings
    }

    @Test("no picture is no first frame")
    func noPictureHoldsNothing() throws {
        let request = try WanRequestMapper.request(for: Self.settings(reference: nil), descriptor: Self.descriptor)
        #expect(request.firstFrame == nil)
    }

    @Test("a picture is the first frame, held exactly: there is no strength to carry")
    func aPictureIsTheFirstFrame() throws {
        var settings = Self.settings(reference: try Self.png())
        settings.referenceStrength = 0.3
        let request = try WanRequestMapper.request(for: settings, descriptor: Self.descriptor)
        #expect(request.firstFrame != nil)
        #expect(Self.descriptor.capabilities.clamp(settings).referenceStrength == 1)
    }

    @Test("something that is not a picture fails before the first step rather than during it")
    func anUnreadablePictureThrows() {
        #expect(throws: (any Error).self) {
            try WanRequestMapper.request(
                for: Self.settings(reference: Data("not a picture".utf8)), descriptor: Self.descriptor)
        }
    }

    @Test("the clip's own settings survive the trip, on the model's grid")
    func theRestOfTheRequestIsUnchanged() throws {
        var settings = Self.settings(reference: nil)
        settings.prompt = "a kite"
        settings.frames = 30
        settings.size = ImageSize(width: 700, height: 500)
        settings.seed = 42
        let request = try WanRequestMapper.request(for: settings, descriptor: Self.descriptor)
        #expect(request.prompt == "a kite")
        // 30 is between two rungs of the 1 + 4k ladder and rounds down to 29.
        #expect(request.frames == 29)
        #expect(request.width == 704)
        #expect(request.height == 512)
        #expect(request.seed == 42)
        #expect(request.frameRate == 24)
    }
}
