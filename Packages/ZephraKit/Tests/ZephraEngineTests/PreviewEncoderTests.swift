import CoreGraphics
import Foundation
import ImageIO
import Testing
import ZephraCore
import ZephraLinkHost

/// What a frame looks like by the time it reaches a phone: JPEG, and over the checkerboard
/// when the model made anything transparent.
@Suite("A preview frame crosses the link as JPEG")
struct PreviewEncoderTests {
    @Test("an opaque frame encodes to the same bytes it always did")
    func opaqueFramesAreUnchanged() throws {
        let frame = Self.preview(alpha: 255)
        let encoded = try #require(PreviewEncoder.encode(frame))

        #expect(encoded.starts(with: [0xFF, 0xD8]), "a JPEG")
        // Twice is the same answer: nothing about the encode depends on what came before it.
        #expect(PreviewEncoder.encode(frame) == encoded)
        let read = try #require(Self.pixels(of: encoded, edge: 16))
        #expect(
            abs(Int(read[0]) - 200) <= 6 && abs(Int(read[1]) - 40) <= 6,
            "the picture's own colour, JPEG's rounding aside")
    }

    @Test("a wholly transparent frame arrives as the checkerboard's two greys")
    func transparentFramesAreComposited() throws {
        let encoded = try #require(PreviewEncoder.encode(Self.preview(alpha: 0)))
        let read = try #require(Self.pixels(of: encoded, edge: 16))

        // Four samples, one in each quadrant. Each is one of the checkerboard's two greys —
        // JPEG is lossy, so near it rather than on it — and both greys are among them, which
        // is what says a pattern was laid down rather than a flat fill. Which quadrant holds
        // which grey is left alone: a bitmap context's rows run the other way from a picture's
        // and the checkerboard reads the same either way.
        let samples = [(2, 2), (10, 2), (2, 10), (10, 10)].map { Int(read[($1 * 16 + $0) * 4]) }
        let greys = [Int(Checkerboard.light), Int(Checkerboard.dark)]
        for sample in samples {
            #expect(
                greys.contains { abs(sample - $0) <= 6 },
                "\(sample) is neither of the checkerboard's greys")
        }
        #expect(
            samples.contains { abs($0 - greys[0]) <= 6 },
            "no light square: the frame was flattened rather than checkered")
        #expect(
            samples.contains { abs($0 - greys[1]) <= 6 },
            "no dark square: the frame was flattened rather than checkered")
    }

    /// A 16 by 16 frame in one colour at one alpha.
    private static func preview(alpha: UInt8) -> GenerationPreview {
        var bytes = [UInt8]()
        for _ in 0..<(16 * 16) { bytes.append(contentsOf: [200, 40, 90, alpha]) }
        return GenerationPreview(width: 16, height: 16, pixels: Data(bytes))
    }

    /// The encoded frame read back as RGBA8.
    private static func pixels(of jpeg: Data, edge: Int) -> [UInt8]? {
        guard let source = CGImageSourceCreateWithData(jpeg as CFData, nil),
            let image = CGImageSourceCreateImageAtIndex(source, 0, nil)
        else { return nil }
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
        return drawn ? bytes : nil
    }
}
