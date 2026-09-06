import Foundation
import Testing

@testable import ZephraCore

@Suite("frame counts in the capabilities")
struct FrameCapabilitiesTests {
    /// A video model's capabilities: clips from 9 to 121 frames on a ladder of eight.
    private let video = ModelCapabilities(
        sizeAlignment: 32,
        sizePresets: [ImageSize(width: 768, height: 512)],
        sizeBounds: 256...1024,
        defaultSize: ImageSize(width: 768, height: 512),
        stepBounds: 8...8,
        defaultSteps: 8,
        guidanceBounds: 0...0,
        defaultGuidance: 0,
        supportsNegativePrompt: false,
        supportsSeed: true,
        frameBounds: 9...121,
        defaultFrames: 49,
        frameAlignment: 8,
        frameRate: 24
    )

    private func settings(frames: Int) -> GenerationSettings {
        GenerationSettings(
            prompt: "x", size: ImageSize(width: 768, height: 512), steps: 8, guidance: 0, seed: 1,
            frames: frames)
    }

    @Test("a picture model pins every request to one frame and offers no duration control")
    func pictureModel() {
        let picture = ModelCatalog.zImageTurbo8bit.capabilities
        #expect(picture.frameBounds == 1...1)
        #expect(!picture.adjustsFrames)
        #expect(!picture.producesVideo)
        #expect(picture.clamp(settings(frames: 49)).frames == 1)
        #expect(GenerationSettings.defaults(for: ModelCatalog.zImageTurbo8bit).frames == 1)
    }

    @Test("a video model rounds a count down to its ladder and keeps it inside the bounds")
    func videoModel() {
        #expect(video.adjustsFrames)
        #expect(video.producesVideo)
        #expect(video.clamp(settings(frames: 49)).frames == 49)
        #expect(video.clamp(settings(frames: 50)).frames == 49)
        #expect(video.clamp(settings(frames: 56)).frames == 49)
        #expect(video.clamp(settings(frames: 57)).frames == 57)
        #expect(video.clamp(settings(frames: 1)).frames == 9)
        #expect(video.clamp(settings(frames: 500)).frames == 121)
    }

    @Test("settings written before clips existed decode as one frame")
    func decodesWithoutFrames() throws {
        let data = try JSONEncoder().encode(settings(frames: 49))
        var older = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        older.removeValue(forKey: "frames")
        let decoded = try JSONDecoder().decode(
            GenerationSettings.self, from: try JSONSerialization.data(withJSONObject: older))
        #expect(decoded.frames == 1)
        let roundTrip = try JSONDecoder().decode(GenerationSettings.self, from: data)
        #expect(roundTrip.frames == 49)
    }

    @Test("a clip's poster is what stands for it, and an image is its own poster")
    func media() {
        let video = GeneratedVideo(poster: Data([1]), mp4: Data([2, 3]), frameCount: 49, frameRate: 24)
        #expect(GeneratedMedia.video(video).posterPNG == Data([1]))
        #expect(GeneratedMedia.image(png: Data([7])).posterPNG == Data([7]))
        #expect(abs(video.seconds - 49.0 / 24.0) < 1e-9)
    }
}
