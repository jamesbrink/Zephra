import CoreGraphics
import Foundation
import ImageIO
import Testing
import UIKit
import UniformTypeIdentifiers
import ZephraStyle

@testable import ZephraMobile

/// What a decoded picture says about its own alpha, which is what the phone's tiles and the
/// viewer's page read before they draw the checkerboard.
@Suite("A decoded picture says whether it carries transparency")
struct DecodedPictureTests {
    @Test("an RGBA picture reads as transparent and an RGB one does not")
    func alphaComesFromTheBitmap() async throws {
        let clear = try #require(await DecodedPicture.from(Self.png(alpha: true)))
        let opaque = try #require(await DecodedPicture.from(Self.png(alpha: false)))

        #expect(clear.cgImage?.hasTransparency == true)
        #expect(opaque.cgImage?.hasTransparency == false)
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
}
