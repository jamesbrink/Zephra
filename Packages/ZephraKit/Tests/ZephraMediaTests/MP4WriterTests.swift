import AVFoundation
import Foundation
import Testing
import ZephraMedia

@Suite("the MP4 writer")
struct MP4WriterTests {
    /// A clip whose frames darken one by one, small enough to encode in a blink.
    private func gradient(frames: Int, width: Int, height: Int) throws -> RGBAFrameSequence {
        var pixels = Data(capacity: frames * width * height * 4)
        for frame in 0..<frames {
            let shade = UInt8(255 - frame * 20)
            for _ in 0..<(width * height) {
                pixels.append(contentsOf: [shade, UInt8(frame * 10), 40, 255])
            }
        }
        return try RGBAFrameSequence(width: width, height: height, frameCount: frames, pixels: pixels)
    }

    @Test("nine frames at 24 fps come back as a playable clip of the same shape and length")
    func roundTrip() async throws {
        let mp4 = try await MP4Writer.encode(try gradient(frames: 9, width: 64, height: 32), frameRate: 24)
        #expect(mp4.count > 500)
        let url = FileManager.default.temporaryDirectory.appending(path: "mp4writer-\(UUID()).mp4")
        try mp4.write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }
        let asset = AVURLAsset(url: url)
        let tracks = try await asset.loadTracks(withMediaType: .video)
        #expect(tracks.count == 1)
        let size = try await tracks[0].load(.naturalSize)
        #expect(Int(size.width) == 64)
        #expect(Int(size.height) == 32)
        let duration = try await asset.load(.duration).seconds
        #expect(abs(duration - 9.0 / 24.0) < 0.001)
        let rate = try await tracks[0].load(.nominalFrameRate)
        #expect(abs(Double(rate) - 24) < 0.01)
    }

    @Test("a buffer that does not match its shape is refused before anything is written")
    func shapeMismatch() {
        #expect(throws: MP4WriterError.pixelCountMismatch(expected: 64 * 32 * 4 * 2, got: 10)) {
            _ = try RGBAFrameSequence(width: 64, height: 32, frameCount: 2, pixels: Data(count: 10))
        }
    }

    @Test("an empty clip is refused")
    func empty() {
        #expect(throws: MP4WriterError.emptyClip) {
            _ = try RGBAFrameSequence(width: 64, height: 32, frameCount: 0, pixels: Data())
        }
    }
}
