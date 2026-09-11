import AVFoundation
import Foundation
import Testing
import ZephraCore
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

@Suite("the MP4 writer, with sound")
struct MP4WriterAudioTests {
    private static func frames(_ count: Int) throws -> RGBAFrameSequence {
        var pixels = Data(capacity: count * 64 * 32 * 4)
        for frame in 0..<count {
            for _ in 0..<(64 * 32) { pixels.append(contentsOf: [UInt8(frame * 5), 30, 40, 255]) }
        }
        return try RGBAFrameSequence(width: 64, height: 32, frameCount: count, pixels: pixels)
    }

    /// A 440 Hz tone, `seconds` long, stereo at 48 kHz.
    static func tone(seconds: Double, rate: Double = 48000) throws -> AudioTrack {
        let frames = Int(seconds * rate)
        var samples: [Float] = []
        samples.reserveCapacity(frames * 2)
        for index in 0..<frames {
            let value = Float(sin(2 * Double.pi * 440 * Double(index) / rate)) * 0.5
            samples.append(value)
            samples.append(value)
        }
        return try AudioTrack(samples: samples, channels: 2, sampleRate: rate)
    }

    @Test("a clip with a track comes back with one video and one audio track of the same length")
    func twoTracks() async throws {
        // Two seconds: longer than one interleaving chunk, so the order the tracks are fed in
        // is exercised rather than a single append of each.
        let mp4 = try await MP4Writer.encode(try Self.frames(48), frameRate: 24, audio: try Self.tone(seconds: 2))
        let url = FileManager.default.temporaryDirectory.appending(path: "mp4audio-\(UUID()).mp4")
        try mp4.write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }
        let asset = AVURLAsset(url: url)
        #expect(try await asset.loadTracks(withMediaType: .video).count == 1)
        let audio = try await asset.loadTracks(withMediaType: .audio)
        #expect(audio.count == 1)
        let audioSeconds = try await audio[0].load(.timeRange).duration.seconds
        #expect(abs(audioSeconds - 2) < 0.1)
        let duration = try await asset.load(.duration).seconds
        #expect(abs(duration - 2) < 0.1)
    }

    @Test("a track that is not whole frames is refused, and says what is wrong with it")
    func oddSamples() {
        #expect(throws: MP4WriterError.unalignedSamples(channels: 2, got: 3)) {
            _ = try AudioTrack(samples: [0, 0, 0], channels: 2, sampleRate: 48000)
        }
    }

    @Test("dropping seconds off the front trims whole frames, and appending joins")
    func trimAndJoin() throws {
        let track = try Self.tone(seconds: 1)
        #expect(track.frames == 48000)
        let trimmed = track.dropping(seconds: 0.25)
        #expect(trimmed.frames == 36000)
        #expect(trimmed.samples.first == track.samples[12000 * 2])
        #expect(track.appending(trimmed).frames == 84000)
    }

    @Test("the stitcher carries sound through when every part has it, trimmed at each join")
    func stitchedSound() async throws {
        let first = try await MP4Writer.encode(try Self.frames(24), frameRate: 24, audio: try Self.tone(seconds: 1))
        let second = try await MP4Writer.encode(try Self.frames(24), frameRate: 24, audio: try Self.tone(seconds: 1))
        let joined = try await MP4Stitcher().stitch([ClipPart(mp4: first), ClipPart(mp4: second, dropLeading: 12)])
        let url = FileManager.default.temporaryDirectory.appending(path: "stitch-audio-\(UUID()).mp4")
        try joined.write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }
        let asset = AVURLAsset(url: url)
        let audio = try await asset.loadTracks(withMediaType: .audio)
        #expect(audio.count == 1)
        let seconds = try await asset.load(.duration).seconds
        #expect(abs(seconds - 1.5) < 0.1, "24 + 12 frames at 24 fps")
        let silent = try await MP4Writer.encode(try Self.frames(24), frameRate: 24)
        let mixed = try await MP4Stitcher().stitch([ClipPart(mp4: first), ClipPart(mp4: silent)])
        let mixedURL = FileManager.default.temporaryDirectory.appending(path: "stitch-mixed-\(UUID()).mp4")
        try mixed.write(to: mixedURL)
        defer { try? FileManager.default.removeItem(at: mixedURL) }
        #expect(try await AVURLAsset(url: mixedURL).loadTracks(withMediaType: .audio).isEmpty, "a silent part silences the join")
    }
}
