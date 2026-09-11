import Foundation
import Testing

@testable import ZephraCore

@Suite("carrying a clip on, in the capabilities and the settings")
struct ContinuationCapabilitiesTests {
    private func continuation(frames: Int) -> ClipContinuation {
        ClipContinuation(
            frames: (0..<frames).map { Data([UInt8($0)]) }, origin: "clip.png", sourceFrameCount: 49)
    }

    private func settings(_ continuation: ClipContinuation?, frames: Int = 49) -> GenerationSettings {
        GenerationSettings(
            prompt: "x", size: ImageSize(width: 768, height: 512), steps: 8, guidance: 0, seed: 1,
            frames: frames, continuation: continuation)
    }

    @Test("a picture model cannot continue a clip and drops one it is handed")
    func pictureModelDrops() {
        let picture = ModelCatalog.zImageTurbo8bit.capabilities
        #expect(!picture.supportsContinuation)
        #expect(picture.clamp(settings(continuation(frames: 9))).continuation == nil)
    }

    @Test("LTX-2.5 holds a tail on its ladder of eight, trimmed to the last frames it can hold")
    func ltxTrimsToItsLadder() {
        let ltx = ModelCatalog.ltx2Distilled4bit.capabilities
        #expect(ltx.supportsContinuation)
        #expect(ltx.defaultContinuationFrames == 17)
        let kept = ltx.clamp(settings(continuation(frames: 12))).continuation
        #expect(kept?.frames.count == 9)
        #expect(kept?.frames.last == Data([11]), "the newest frames are the ones kept")
        #expect(ltx.clamp(settings(continuation(frames: 40))).continuation?.frames.count == 25)
        #expect(ltx.clamp(settings(continuation(frames: 1))).continuation?.frames.count == 1)
        #expect(ltx.clamp(settings(continuation(frames: 0))).continuation == nil)
    }

    @Test("a held run is trimmed to leave room for frames the model makes")
    func heldRunLeavesRoom() {
        let ltx = ModelCatalog.ltx2Distilled4bit.capabilities
        let held = continuation(frames: 17)
        // The shortest clip LTX makes cannot hold 17 frames it did not make: a pass that is
        // all held frames has every frame dropped at the join and comes out empty.
        #expect(ltx.clamp(settings(held, frames: 9)).continuation?.frames.count == 1)
        #expect(ltx.clamp(settings(held, frames: 17)).continuation?.frames.count == 9)
        #expect(ltx.clamp(settings(held, frames: 25)).continuation?.frames.count == 17)
        #expect(ltx.clamp(settings(held, frames: 49)).continuation?.frames.count == 17, "a long clip trims nothing")
    }

    @Test("Wan holds the last frame alone")
    func wanHoldsOne() {
        let wan = ModelCatalog.wan22TI2V5B4bit.capabilities
        #expect(wan.clamp(settings(continuation(frames: 9))).continuation?.frames.count == 1)
        #expect(
            wan.clamp(settings(continuation(frames: 9), frames: 5)).continuation?.frames.count == 1,
            "one held frame still leaves room in Wan's shortest clip")
    }

    @Test("a continuation survives the round trip through JSON, and an older file reads none")
    func codable() throws {
        let encoded = try JSONEncoder().encode(settings(continuation(frames: 2)))
        let decoded = try JSONDecoder().decode(GenerationSettings.self, from: encoded)
        #expect(decoded.continuation?.frames.count == 2)
        #expect(decoded.continuation?.contextFrames == 2)
        let older = Data(#"{"prompt":"x","size":{"width":8,"height":8},"steps":1,"guidance":0,"seed":1}"#.utf8)
        #expect(try JSONDecoder().decode(GenerationSettings.self, from: older).continuation == nil)
    }

    @Test("dropping the pixels keeps the count and the origin")
    func withoutPixels() {
        let bare = continuation(frames: 9).withoutPixels()
        #expect(bare.frames.isEmpty)
        #expect(bare.contextFrames == 9)
        #expect(bare.origin == "clip.png")
    }

    @Test("a clip is carried on by its own model when it can, else by the animator")
    func continuer() {
        #expect(ModelCatalog.continuer(for: ModelCatalog.ltx2Distilled4bit.id)?.id == ModelCatalog.ltx2Distilled4bit.id)
        #expect(ModelCatalog.continuer(for: ModelCatalog.wan22TI2V5B4bit.id)?.id == ModelCatalog.wan22TI2V5B4bit.id)
        #expect(ModelCatalog.continuer(for: "nothing-like-this")?.id == ModelCatalog.animator()?.id)
    }
}
