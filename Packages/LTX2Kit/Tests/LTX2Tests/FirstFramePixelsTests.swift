import CoreGraphics
import Foundation
import MLX
import Testing

@testable import LTX2

@Suite("a first frame is scaled to cover the clip and cropped to the middle")
struct FirstFramePixelsTests {
    /// A picture whose left half is one colour and right half another, so a crop that took the
    /// wrong side, or none at all, changes what comes back.
    static func halves(width: Int, height: Int) throws -> CGImage {
        let context = try #require(
            CGContext(
                data: nil, width: width, height: height, bitsPerComponent: 8,
                bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue))
        context.setFillColor(CGColor(red: 1, green: 0, blue: 0, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width / 2, height: height))
        context.setFillColor(CGColor(red: 0, green: 0, blue: 1, alpha: 1))
        context.fill(CGRect(x: width / 2, y: 0, width: width - width / 2, height: height))
        return try #require(context.makeImage())
    }

    @Test("the picture comes back as one frame, channels first, in minus one to one")
    func shapeAndRange() throws {
        let pixels = try LTX2FirstFramePixels.pixels(
            from: Self.halves(width: 64, height: 64), width: 96, height: 64)
        #expect(pixels.shape == [1, 3, 1, 64, 96])
        #expect(MLX.max(pixels).item(Float.self) <= 1)
        #expect(MLX.min(pixels).item(Float.self) >= -1)
        // Pure red on the left half and pure blue on the right, both at the ends of the range.
        #expect(pixels[0, 0, 0, 32, 8].item(Float.self) == 1)
        #expect(pixels[0, 2, 0, 32, 8].item(Float.self) == -1)
        #expect(pixels[0, 2, 0, 32, 88].item(Float.self) == 1)
    }

    @Test("a wide picture in a tall frame is covered and cropped, never letterboxed")
    func aWidePictureIsCropped() throws {
        // 200 x 100 into 100 x 100: the larger ratio is 1, so the width overflows by 100 and
        // fifty pixels come off each side.
        let rect = LTX2FirstFramePixels.fill(
            try Self.halves(width: 200, height: 100), width: 100, height: 100)
        #expect(rect == CGRect(x: -50, y: 0, width: 200, height: 100))
    }

    @Test("a tall picture in a wide frame is covered the other way")
    func aTallPictureIsCropped() throws {
        // 100 x 200 into 200 x 100: the larger ratio is 2, so the height becomes 400 and a
        // hundred and fifty pixels come off top and bottom.
        let rect = LTX2FirstFramePixels.fill(
            try Self.halves(width: 100, height: 200), width: 200, height: 100)
        #expect(rect == CGRect(x: 0, y: -150, width: 200, height: 400))
    }

    @Test("a picture already the frame's shape is neither scaled nor moved")
    func anExactPictureIsLeftAlone() throws {
        let rect = LTX2FirstFramePixels.fill(
            try Self.halves(width: 96, height: 64), width: 96, height: 64)
        #expect(rect == CGRect(x: 0, y: 0, width: 96, height: 64))
    }

    @Test("nothing is letterboxed: the drawn rectangle always covers the frame")
    func everyShapeCovers() throws {
        for (pictureWidth, pictureHeight) in [(200, 100), (100, 200), (33, 97), (1, 1000)] {
            let rect = LTX2FirstFramePixels.fill(
                try Self.halves(width: pictureWidth, height: pictureHeight), width: 96, height: 64)
            #expect(rect.minX <= 0.0001 && rect.maxX >= 95.9999, "\(pictureWidth)x\(pictureHeight)")
            #expect(rect.minY <= 0.0001 && rect.maxY >= 63.9999, "\(pictureWidth)x\(pictureHeight)")
        }
    }
}
