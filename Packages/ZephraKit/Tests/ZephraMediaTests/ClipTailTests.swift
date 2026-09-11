import Foundation
import ImageIO
import Testing
import ZephraMedia

/// A clip's last frames are really its last, and a file with no video track has none to read.
///
/// The fixture is a committed clip, `Fixtures/red-then-blue.mp4`: four 32 x 32 frames at 4 fps,
/// three red and then one blue, so a decode that landed on the wrong end reads as the wrong
/// colour rather than merely as "some frame". Committed rather than written here so the app's
/// own suite could once read it too: an `AVAssetWriter` run inside the app-hosted test process
/// left CoreMedia's writer threads parked and the host never exited. This package's tests may
/// write clips; the fixture stays for the colour it pins.
@Suite("a clip's tail")
struct ClipTailTests {
    static var fixture: URL {
        get throws {
            try #require(Bundle.module.url(forResource: "red-then-blue", withExtension: "mp4", subdirectory: "Fixtures"))
        }
    }

    @Test("the last frame is the clip's last colour, not its first")
    func lastNotFirst() async throws {
        let frames = try await ClipTail.read(from: try Self.fixture, frames: 1)
        #expect(frames.count == 1)
        let last = try #require(frames.last)
        let pixel = try #require(Self.averagePixel(of: last))
        #expect(pixel.blue > pixel.red, "the last frame was written blue, not red")
    }

    @Test("asking for more frames than the clip has gives the whole clip, oldest first")
    func wholeClip() async throws {
        let frames = try await ClipTail.read(from: try Self.fixture, frames: 9)
        #expect(frames.count == 4)
        let firstFrame = try #require(frames.first)
        let lastFrame = try #require(frames.last)
        let first = try #require(Self.averagePixel(of: firstFrame))
        let last = try #require(Self.averagePixel(of: lastFrame))
        #expect(first.red > first.blue)
        #expect(last.blue > last.red)
    }

    @Test("a clip still in memory reads its tail the same way")
    func tailOfDataInMemory() async throws {
        let mp4 = try Data(contentsOf: try Self.fixture)
        let frames = try await ClipTail.read(fromData: mp4, frames: 2)
        #expect(frames.count == 2)
        let lastFrame = try #require(frames.last)
        let pixel = try #require(Self.averagePixel(of: lastFrame))
        #expect(pixel.blue > pixel.red)
    }

    @Test("a file with no video track is refused")
    func noVideoTrack() async throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("clip-tail-\(UUID().uuidString)")
            .appendingPathExtension("mp4")
        try Data("not a real clip".utf8).write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }
        await #expect(throws: MP4WriterError.notAClip) {
            _ = try await ClipTail.read(from: url, frames: 1)
        }
    }

    /// The whole picture scaled down to one pixel, which for a solid-colour frame is that
    /// colour, minor compression noise aside.
    static func averagePixel(of png: Data) -> (red: UInt8, green: UInt8, blue: UInt8)? {
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
