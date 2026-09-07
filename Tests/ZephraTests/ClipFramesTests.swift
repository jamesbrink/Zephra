import AVFoundation
import CoreVideo
import Foundation
import Testing

@testable import Zephra

/// A clip's last frame is really its last, and a file with no video track has none to read.
///
/// The fixture clips are built by hand with `AVAssetWriter` rather than through `MP4Writer` (in
/// `ZephraMedia`, which the app target does not depend on): a nine-frame clip whose first frame
/// is red and whose last is blue, so a decode that landed on the wrong end reads as the wrong
/// colour rather than merely as "some frame".
@Suite("a clip's last frame")
struct ClipFramesTests {
    @Test("the last frame is the clip's last colour, not its first")
    func lastNotFirst() async throws {
        let url = try await Self.makeClip(
            colours: [(255, 0, 0), (255, 0, 0), (255, 0, 0), (0, 0, 255)], width: 32, height: 32,
            frameRate: 4)
        defer { try? FileManager.default.removeItem(at: url) }

        let png = try #require(ClipFrames.lastFrame(of: url))
        let pixel = try #require(Self.averagePixel(of: png))
        #expect(pixel.blue > pixel.red, "the last frame was written blue, not red")
    }

    @Test("a clip still in memory reads its last frame the same way")
    func lastFrameOfDataInMemory() async throws {
        let url = try await Self.makeClip(
            colours: [(255, 0, 0), (0, 0, 255)], width: 32, height: 32, frameRate: 2)
        defer { try? FileManager.default.removeItem(at: url) }
        let mp4 = try Data(contentsOf: url)

        let png = try #require(ClipFrames.lastFrame(ofMP4Data: mp4))
        let pixel = try #require(Self.averagePixel(of: png))
        #expect(pixel.blue > pixel.red)
    }

    @Test("a file with no video track has no last frame")
    func noVideoTrack() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("clip-frames-\(UUID().uuidString)")
            .appendingPathExtension("mp4")
        try Data("not a real clip".utf8).write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }

        #expect(ClipFrames.lastFrame(of: url) == nil)
    }

    @Test("bytes that are not a clip at all have no last frame either")
    func notAClipAtAll() {
        #expect(ClipFrames.lastFrame(ofMP4Data: Data("not a real clip".utf8)) == nil)
    }

    // MARK: - Fixture

    /// A short H.264 clip of solid-colour frames, one entry of `colours` each, at `frameRate`
    /// frames per second.
    private static func makeClip(
        colours: [(UInt8, UInt8, UInt8)], width: Int, height: Int, frameRate: Int32
    ) async throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("clip-frames-fixture-\(UUID().uuidString)")
            .appendingPathExtension("mp4")
        let writer = try AVAssetWriter(outputURL: url, fileType: .mp4)
        let input = AVAssetWriterInput(
            mediaType: .video,
            outputSettings: [
                AVVideoCodecKey: AVVideoCodecType.h264,
                AVVideoWidthKey: width,
                AVVideoHeightKey: height,
            ])
        input.expectsMediaDataInRealTime = false
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(
            assetWriterInput: input,
            sourcePixelBufferAttributes: [
                kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
                kCVPixelBufferWidthKey as String: width,
                kCVPixelBufferHeightKey as String: height,
            ])
        writer.add(input)
        writer.startWriting()
        writer.startSession(atSourceTime: .zero)
        for (index, colour) in colours.enumerated() {
            let buffer = try Self.pixelBuffer(width: width, height: height, colour: colour)
            let time = CMTime(value: CMTimeValue(index), timescale: frameRate)
            adaptor.append(buffer, withPresentationTime: time)
        }
        input.markAsFinished()
        await writer.finishWriting()
        guard writer.status == .completed else {
            throw ClipFramesFixtureError.encodingFailed(writer.error?.localizedDescription ?? "?")
        }
        return url
    }

    private static func pixelBuffer(
        width: Int, height: Int, colour: (UInt8, UInt8, UInt8)
    ) throws -> CVPixelBuffer {
        var buffer: CVPixelBuffer?
        let status = CVPixelBufferCreate(
            kCFAllocatorDefault, width, height, kCVPixelFormatType_32BGRA, nil, &buffer)
        guard status == kCVReturnSuccess, let buffer else {
            throw ClipFramesFixtureError.encodingFailed("CVPixelBufferCreate failed")
        }
        CVPixelBufferLockBaseAddress(buffer, [])
        defer { CVPixelBufferUnlockBaseAddress(buffer, []) }
        let base = CVPixelBufferGetBaseAddress(buffer)!.assumingMemoryBound(to: UInt8.self)
        let bytesPerRow = CVPixelBufferGetBytesPerRow(buffer)
        for row in 0..<height {
            for column in 0..<width {
                let offset = row * bytesPerRow + column * 4
                base[offset] = colour.2
                base[offset + 1] = colour.1
                base[offset + 2] = colour.0
                base[offset + 3] = 255
            }
        }
        return buffer
    }

    /// The whole picture scaled down to one pixel, which for a solid-colour frame is that
    /// colour, minor compression noise aside.
    private static func averagePixel(of png: Data) -> (red: UInt8, green: UInt8, blue: UInt8)? {
        guard let source = CGImageSourceCreateWithData(png as CFData, nil),
            let image = CGImageSourceCreateImageAtIndex(source, 0, nil)
        else { return nil }
        var pixel = [UInt8](repeating: 0, count: 4)
        guard
            let context = CGContext(
                data: &pixel, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { return nil }
        context.draw(image, in: CGRect(x: 0, y: 0, width: 1, height: 1))
        return (pixel[0], pixel[1], pixel[2])
    }
}

private enum ClipFramesFixtureError: Error {
    case encodingFailed(String)
}
