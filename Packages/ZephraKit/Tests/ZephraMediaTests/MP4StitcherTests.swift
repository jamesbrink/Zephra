import AVFoundation
import Foundation
import Testing
import ZephraCore
import ZephraMedia

@Suite("the stitcher joins clips end to end")
struct MP4StitcherTests {
    /// A clip of one solid colour per frame, so a frame's origin can be read off its colour.
    private static func clip(colours: [(UInt8, UInt8, UInt8)], width: Int = 64, height: Int = 32) async throws -> Data {
        var pixels = Data(capacity: colours.count * width * height * 4)
        for (r, g, b) in colours {
            for _ in 0..<(width * height) { pixels.append(contentsOf: [r, g, b, 255]) }
        }
        let frames = try RGBAFrameSequence(width: width, height: height, frameCount: colours.count, pixels: pixels)
        return try await MP4Writer.encode(frames, frameRate: 24)
    }

    private static func frameCount(of mp4: Data) async throws -> (frames: Int, seconds: Double) {
        let url = FileManager.default.temporaryDirectory.appending(path: "stitch-\(UUID()).mp4")
        try mp4.write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }
        let tail = try await ClipTail.read(from: url, frames: 1000)
        let seconds = try await AVURLAsset(url: url).load(.duration).seconds
        return (tail.count, seconds)
    }

    @Test("two clips become one, the second's held frames dropped, and the join is the second's first new frame")
    func joinDroppingContext() async throws {
        let red: (UInt8, UInt8, UInt8) = (220, 20, 20)
        let blue: (UInt8, UInt8, UInt8) = (20, 20, 220)
        let green: (UInt8, UInt8, UInt8) = (20, 200, 20)
        let first = try await Self.clip(colours: [red, red, red, red, blue])
        // The second clip starts on the first's last frame, re-decoded, then goes green.
        let second = try await Self.clip(colours: [blue, green, green, green])
        let stitched = try await MP4Stitcher().stitch([
            ClipPart(mp4: first), ClipPart(mp4: second, dropLeading: 1),
        ])
        let counted = try await Self.frameCount(of: stitched)
        #expect(counted.frames == 8)
        #expect(abs(counted.seconds - 8.0 / 24.0) < 0.001)
        let url = FileManager.default.temporaryDirectory.appending(path: "stitch-\(UUID()).mp4")
        try stitched.write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }
        let frames = try await ClipTail.read(from: url, frames: 8)
        let seam = try #require(ClipTailTests.averagePixel(of: frames[4]))
        #expect(seam.blue > seam.green && seam.blue > seam.red, "frame 4 is the first clip's last frame")
        let after = try #require(ClipTailTests.averagePixel(of: frames[5]))
        #expect(after.green > after.blue && after.green > after.red, "frame 5 is the second clip's first new frame")
    }

    @Test("clips of different sizes are refused before anything is written")
    func mismatchedSizes() async throws {
        let first = try await Self.clip(colours: [(1, 2, 3), (1, 2, 3)])
        let second = try await Self.clip(colours: [(1, 2, 3), (1, 2, 3)], width: 32, height: 32)
        await #expect(throws: MP4WriterError.mismatchedParts) {
            _ = try await MP4Stitcher().stitch([ClipPart(mp4: first), ClipPart(mp4: second)])
        }
    }

    @Test("no parts is an empty clip")
    func noParts() async {
        await #expect(throws: MP4WriterError.emptyClip) {
            _ = try await MP4Stitcher().stitch([])
        }
    }
}
