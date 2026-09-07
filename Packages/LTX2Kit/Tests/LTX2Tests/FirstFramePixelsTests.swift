import CoreGraphics
import Foundation
import MLX
import Testing

@testable import LTX2

@Suite("a first frame is scaled to cover the clip and cropped to the middle")
struct FirstFramePixelsTests {
    /// A picture split into four quadrants of distinct colours — red (top-left), green
    /// (top-right), blue (bottom-left), yellow (bottom-right) — so a crop that took the wrong
    /// side on either axis, or none at all, changes what comes back. Two colours split only
    /// left and right (the old fixture) would pass a top/bottom flip undetected, since both
    /// halves would still read correctly on their own axis; four distinct quadrants catch that
    /// too. `y` in CGContext's own coordinate system is 0 at the bottom, so the "top" half in
    /// user space (the higher `y`) is what a viewer calls the top of the picture.
    static func quadrants(width: Int, height: Int) throws -> CGImage {
        // `CGColor(red:green:blue:alpha:)` builds its colour in a generic RGB space, not this
        // context's device one, so filling with it forces a colour-matched conversion that
        // shifts a "0" component a little off zero. Building each colour directly in the
        // context's own colour space keeps the fixture's bytes exact.
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let context = try #require(
            CGContext(
                data: nil, width: width, height: height, bitsPerComponent: 8,
                bytesPerRow: width * 4, space: colorSpace,
                bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue))
        let halfWidth = width / 2
        let halfHeight = height / 2
        func fill(_ rect: CGRect, red: CGFloat, green: CGFloat, blue: CGFloat) {
            context.setFillColor(CGColor(colorSpace: colorSpace, components: [red, green, blue, 1])!)
            context.fill(rect)
        }
        fill(
            CGRect(x: 0, y: halfHeight, width: halfWidth, height: height - halfHeight),
            red: 1, green: 0, blue: 0)
        fill(
            CGRect(x: halfWidth, y: halfHeight, width: width - halfWidth, height: height - halfHeight),
            red: 0, green: 1, blue: 0)
        fill(CGRect(x: 0, y: 0, width: halfWidth, height: halfHeight), red: 0, green: 0, blue: 1)
        fill(
            CGRect(x: halfWidth, y: 0, width: width - halfWidth, height: halfHeight),
            red: 1, green: 1, blue: 0)
        return try #require(context.makeImage())
    }

    @Test("the picture comes back as one frame, channels first, in minus one to one")
    func shapeAndRange() throws {
        let pixels = try LTX2FirstFramePixels.pixels(
            from: Self.quadrants(width: 64, height: 64), width: 96, height: 64)
        #expect(pixels.shape == [1, 3, 1, 64, 96])
        #expect(MLX.max(pixels).item(Float.self) <= 1)
        #expect(MLX.min(pixels).item(Float.self) >= -1)
        // A row above the middle: red on the left, green on the right.
        #expect(pixels[0, 0, 0, 8, 8].item(Float.self) == 1)
        #expect(pixels[0, 1, 0, 8, 8].item(Float.self) == -1)
        #expect(pixels[0, 1, 0, 8, 88].item(Float.self) == 1)
        #expect(pixels[0, 0, 0, 8, 88].item(Float.self) == -1)
        // A row below the middle: blue on the left, yellow on the right. A top/bottom flip would
        // put red and green here instead.
        #expect(pixels[0, 2, 0, 56, 8].item(Float.self) == 1)
        #expect(pixels[0, 0, 0, 56, 8].item(Float.self) == -1)
        #expect(pixels[0, 0, 0, 56, 88].item(Float.self) == 1)
        #expect(pixels[0, 1, 0, 56, 88].item(Float.self) == 1)
        #expect(pixels[0, 2, 0, 56, 88].item(Float.self) == -1)
    }

    @Test("a wide picture in a tall frame is covered and cropped, never letterboxed")
    func aWidePictureIsCropped() throws {
        // 200 x 100 into 100 x 100: the larger ratio is 1, so the width overflows by 100 and
        // fifty pixels come off each side.
        let rect = LTX2FirstFramePixels.fill(
            try Self.quadrants(width: 200, height: 100), width: 100, height: 100)
        #expect(rect == CGRect(x: -50, y: 0, width: 200, height: 100))
    }

    @Test("a tall picture in a wide frame is covered the other way")
    func aTallPictureIsCropped() throws {
        // 100 x 200 into 200 x 100: the larger ratio is 2, so the height becomes 400 and a
        // hundred and fifty pixels come off top and bottom.
        let rect = LTX2FirstFramePixels.fill(
            try Self.quadrants(width: 100, height: 200), width: 200, height: 100)
        #expect(rect == CGRect(x: 0, y: -150, width: 200, height: 400))
    }

    @Test("a picture already the frame's shape is neither scaled nor moved")
    func anExactPictureIsLeftAlone() throws {
        let rect = LTX2FirstFramePixels.fill(
            try Self.quadrants(width: 96, height: 64), width: 96, height: 64)
        #expect(rect == CGRect(x: 0, y: 0, width: 96, height: 64))
    }

    @Test("nothing is letterboxed: the drawn rectangle always covers the frame")
    func everyShapeCovers() throws {
        for (pictureWidth, pictureHeight) in [(200, 100), (100, 200), (33, 97), (1, 1000)] {
            let rect = LTX2FirstFramePixels.fill(
                try Self.quadrants(width: pictureWidth, height: pictureHeight), width: 96, height: 64)
            #expect(rect.minX <= 0.0001 && rect.maxX >= 95.9999, "\(pictureWidth)x\(pictureHeight)")
            #expect(rect.minY <= 0.0001 && rect.maxY >= 63.9999, "\(pictureWidth)x\(pictureHeight)")
        }
    }
}
