import Testing
import ZephraCore

@testable import ZephraBackendLTX2

@Suite("one stage or two")
struct LTX2StagePlanTests {
    private let plain = InferenceEnvironment()

    @Test("the default frame runs two stages; a cheap preset and an odd size run one")
    func sizeRule() {
        #expect(LTX2StagePlan.twoStage(width: 768, height: 512, environment: plain))
        #expect(LTX2StagePlan.twoStage(width: 512, height: 768, environment: plain))
        #expect(LTX2StagePlan.twoStage(width: 1024, height: 576, environment: plain))
        #expect(!LTX2StagePlan.twoStage(width: 512, height: 288, environment: plain), "already cheap")
        #expect(!LTX2StagePlan.twoStage(width: 640, height: 384, environment: plain), "short edge under 512")
        #expect(!LTX2StagePlan.twoStage(width: 960, height: 544, environment: plain), "544 is not on the grid of 64")
    }

    @Test("the switch forces either way, but never a size that cannot be halved")
    func override() {
        let one = InferenceEnvironment(videoStages: 1)
        let two = InferenceEnvironment(videoStages: 2)
        #expect(!LTX2StagePlan.twoStage(width: 768, height: 512, environment: one))
        #expect(LTX2StagePlan.twoStage(width: 640, height: 384, environment: two))
        #expect(!LTX2StagePlan.twoStage(width: 512, height: 288, environment: two), "288 is not on the grid of 64")
        #expect(!LTX2StagePlan.twoStage(width: 960, height: 544, environment: two))
    }
}
