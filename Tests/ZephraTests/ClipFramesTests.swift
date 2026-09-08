import Foundation
import ImageIO
import Testing

@testable import Zephra

/// A clip's last frame is really its last, and a file with no video track has none to read.
///
/// The fixture is a committed clip, `Fixtures/red-then-blue.mp4`: four 32 x 32 frames at 4 fps,
/// three red and then one blue, so a decode that landed on the wrong end reads as the wrong
/// colour rather than merely as "some frame". It is committed rather than written here on
/// purpose: an `AVAssetWriter` run inside the app-hosted test process left CoreMedia's writer
/// threads parked after the suite, the frozen host never exited, and `make test-app` waited on
/// it for good. Reading a clip leaves nothing behind.
@Suite("a clip's last frame")
struct ClipFramesTests {
    private static var fixture: URL {
        get throws {
            try #require(
                Bundle(for: FixtureAnchor.self).url(
                    forResource: "red-then-blue", withExtension: "mp4", subdirectory: "Fixtures"))
        }
    }

    @Test("the last frame is the clip's last colour, not its first")
    func lastNotFirst() async throws {
        let png = try #require(await ClipFrames.lastFrame(of: try Self.fixture))
        let pixel = try #require(Self.averagePixel(of: png))
        #expect(pixel.blue > pixel.red, "the last frame was written blue, not red")
    }

    @Test("a clip still in memory reads its last frame the same way")
    func lastFrameOfDataInMemory() async throws {
        let mp4 = try Data(contentsOf: try Self.fixture)
        let png = try #require(await ClipFrames.lastFrame(ofMP4Data: mp4))
        let pixel = try #require(Self.averagePixel(of: png))
        #expect(pixel.blue > pixel.red)
    }

    @Test("a file with no video track has no last frame")
    func noVideoTrack() async throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("clip-frames-\(UUID().uuidString)")
            .appendingPathExtension("mp4")
        try Data("not a real clip".utf8).write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }
        #expect(await ClipFrames.lastFrame(of: url) == nil)
    }

    @Test("bytes that are not a clip at all have no last frame either")
    func notAClipAtAll() async {
        #expect(await ClipFrames.lastFrame(ofMP4Data: Data("not a real clip".utf8)) == nil)
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

/// Something `Bundle(for:)` can find the test bundle by; Swift Testing has no `Bundle.module`
/// in an Xcode test target.
private final class FixtureAnchor {}
