import AppKit
import CoreGraphics
import Foundation
import ImageIO
import Testing
import UniformTypeIdentifiers
import ZephraStyle

@testable import Zephra

/// What a decoded picture says about its own alpha, which is the one thing every view asks
/// before it decides the ground under a picture.
@Suite("A decoded picture says whether it carries transparency")
struct DrawnPictureTests {
    @Test("an RGBA picture reads as transparent and an RGB one does not")
    func alphaComesFromTheBitmap() throws {
        let clear = try #require(Self.decode(Self.png(alpha: true)))
        let opaque = try #require(Self.decode(Self.png(alpha: false)))

        #expect(clear.hasTransparency)
        #expect(!opaque.hasTransparency)
        #expect(DrawnPicture(clear).hasAlpha)
        #expect(!DrawnPicture(opaque).hasAlpha)
    }

    @Test("the cache hands a view what it decoded, alpha and all")
    func theCacheCarriesTheAnswer() async throws {
        let cache = ImageCache()
        let picture = try #require(await cache.referenceThumbnail(Self.png(alpha: true)))

        #expect(picture.hasAlpha)
        #expect(picture.image.size != .zero, "the pixels came with it")
    }

    /// A two-by-two PNG, written with or without an alpha channel.
    private static func png(alpha: Bool) -> Data {
        let (width, height) = (2, 2)
        var bytes = [UInt8](repeating: 0, count: width * height * 4)
        for pixel in 0..<(width * height) {
            bytes[pixel * 4] = 200
            bytes[pixel * 4 + 1] = 40
            bytes[pixel * 4 + 2] = 90
            bytes[pixel * 4 + 3] = pixel == 0 ? 0 : 255
        }
        let info: CGImageAlphaInfo = alpha ? .last : .noneSkipLast
        let provider = CGDataProvider(data: Data(bytes) as CFData)!
        let image = CGImage(
            width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32,
            bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGBitmapInfo(rawValue: info.rawValue), provider: provider,
            decode: nil, shouldInterpolate: false, intent: .defaultIntent)!
        let output = NSMutableData()
        let destination = CGImageDestinationCreateWithData(
            output, UTType.png.identifier as CFString, 1, nil)!
        CGImageDestinationAddImage(destination, image, nil)
        _ = CGImageDestinationFinalize(destination)
        return output as Data
    }

    private static func decode(_ data: Data) -> CGImage? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        return CGImageSourceCreateImageAtIndex(source, 0, nil)
    }
}
