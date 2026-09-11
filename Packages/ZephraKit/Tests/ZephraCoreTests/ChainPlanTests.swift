import Foundation
import Testing

@testable import ZephraCore

@Suite("a clip longer than one pass, as the passes that make it")
struct ChainPlanTests {
    static let ltx = ModelCatalog.ltx2Distilled4bit.capabilities
    static let wan = ModelCatalog.wan22TI2V5B4bit.capabilities

    @Test("one pass is one segment, bounded and on the ladder")
    func onePass() {
        #expect(ChainPlan.segments(frames: 49, capabilities: Self.ltx) == [49])
        #expect(ChainPlan.segments(frames: 121, capabilities: Self.ltx) == [121])
        #expect(ChainPlan.segments(frames: 50, capabilities: Self.ltx) == [49])
        #expect(ChainPlan.segments(frames: 3, capabilities: Self.ltx) == [9])
    }

    @Test("a longer clip is a full pass and then passes of context plus new frames, exactly the count asked")
    func chained() {
        // 241 frames on LTX: 121, then 17 held + 104 new, then 17 held + 16 new.
        let segments = ChainPlan.segments(frames: 241, capabilities: Self.ltx)
        #expect(segments == [121, 121, 33])
        #expect(ChainPlan.joinedFrames(segments, context: 17) == 241)
        for length in segments { #expect((length - 1) % 8 == 0) }
        // Wan holds one frame, so a pass adds 120.
        let wan = ChainPlan.segments(frames: 241, capabilities: Self.wan)
        #expect(wan == [121, 121])
        #expect(ChainPlan.joinedFrames(wan, context: 1) == 241)
    }

    @Test("four passes is the most, and a picture model has one")
    func bounds() {
        #expect(ChainPlan.maxFrames(Self.ltx) == 121 + 3 * 104)
        #expect(ChainPlan.maxFrames(Self.wan) == 121 + 3 * 120)
        #expect(ChainPlan.segments(frames: 10_000, capabilities: Self.ltx).count == 4)
        let picture = ModelCatalog.zImageTurbo8bit.capabilities
        #expect(ChainPlan.maxFrames(picture) == 1)
        #expect(ChainPlan.segments(frames: 49, capabilities: picture) == [1])
    }
}
