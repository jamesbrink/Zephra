import CoreGraphics
import Foundation
import ImageIO
import Testing
import UniformTypeIdentifiers
import ZephraCore
import ZephraLinkHost
import ZephraTestSupport

@testable import Zephra

/// What a picture looks like by the time a phone's grid cell draws it: JPEG, and over the
/// checkerboard when the picture it was made from carries transparency.
@Suite("A thumbnail crosses the link as JPEG, checkered when it has to be")
struct CompanionThumbnailsTests {
    @Test("a transparent picture's thumbnail is the checkerboard's two greys")
    func transparentThumbnailsAreCheckered() async throws {
        let scratch = Scratch()
        let url = try scratch.make("clear.png")
        try Self.png(alpha: 0).write(to: url)
        let supply = CompanionThumbnails(folder: ThumbnailFolder(directory: scratch.url("thumbs")))

        let jpeg = try #require(await supply.thumbnail(for: url, pixels: 32))

        #expect(jpeg.starts(with: [0xFF, 0xD8]), "a JPEG, as BlobStart names")
        let read = try #require(Self.pixels(of: jpeg))
        let greys = [Int(Checkerboard.light), Int(Checkerboard.dark)]
        for sample in read {
            #expect(
                greys.contains { abs(sample - $0) <= 8 },
                "\(sample) is neither of the checkerboard's greys")
        }
        #expect(read.contains { abs($0 - greys[0]) <= 8 } && read.contains { abs($0 - greys[1]) <= 8 },
            "both squares are there, so a pattern was laid down rather than a flat fill")
    }

    @Test("an opaque picture's thumbnail is the picture, unchanged")
    func opaqueThumbnailsAreUntouched() async throws {
        let scratch = Scratch()
        let url = try scratch.make("solid.png")
        try Self.png(alpha: 255).write(to: url)
        let supply = CompanionThumbnails(folder: ThumbnailFolder(directory: scratch.url("thumbs")))

        let jpeg = try #require(await supply.thumbnail(for: url, pixels: 32))
        let read = try #require(Self.pixels(of: jpeg))

        #expect(read.allSatisfy { abs($0 - 200) <= 8 }, "the picture's own red, JPEG aside")
    }

    /// A 32 by 32 PNG in one colour at one alpha.
    private static func png(alpha: UInt8) throws -> Data {
        let edge = 32
        var bytes = [UInt8]()
        for _ in 0..<(edge * edge) { bytes.append(contentsOf: [200, 40, 90, alpha]) }
        let provider = try #require(CGDataProvider(data: Data(bytes) as CFData))
        let image = try #require(
            CGImage(
                width: edge, height: edge, bitsPerComponent: 8, bitsPerPixel: 32,
                bytesPerRow: edge * 4, space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.last.rawValue),
                provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent))
        let output = NSMutableData()
        let destination = try #require(
            CGImageDestinationCreateWithData(output, UTType.png.identifier as CFString, 1, nil))
        CGImageDestinationAddImage(destination, image, nil)
        #expect(CGImageDestinationFinalize(destination))
        return output as Data
    }

    /// The red channel of four samples, one in each quadrant of the encoded thumbnail.
    private static func pixels(of jpeg: Data) -> [Int]? {
        guard let source = CGImageSourceCreateWithData(jpeg as CFData, nil),
            let image = CGImageSourceCreateImageAtIndex(source, 0, nil),
            image.width >= 16, image.height >= 16
        else { return nil }
        let edge = image.width
        var bytes = [UInt8](repeating: 0, count: edge * edge * 4)
        let drawn = bytes.withUnsafeMutableBytes { buffer -> Bool in
            guard let context = CGContext(
                data: buffer.baseAddress, width: edge, height: edge, bitsPerComponent: 8,
                bytesPerRow: edge * 4, space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)
            else { return false }
            context.draw(image, in: CGRect(x: 0, y: 0, width: edge, height: edge))
            return true
        }
        guard drawn else { return nil }
        // The middle of each of the first four cells, so two light squares and two dark ones
        // are sampled rather than four of the same parity.
        let half = Checkerboard.cell / 2
        let far = Checkerboard.cell + half
        return [(half, half), (far, half), (half, far), (far, far)]
            .map { Int(bytes[($1 * edge + $0) * 4]) }
    }
}
