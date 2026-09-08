import Testing

@testable import Zephra

@Suite("One Zephra at a time")
struct SingleInstanceTests {
    @Test("a launch stands down when another copy of the app is running")
    func standsDownForAnother() {
        #expect(SingleInstance.shouldYield(runningPIDs: [401, 977], own: 977, previewState: nil))
    }

    @Test("a launch that finds only itself, or nothing, carries on")
    func carriesOnAlone() {
        #expect(!SingleInstance.shouldYield(runningPIDs: [977], own: 977, previewState: nil))
        #expect(!SingleInstance.shouldYield(runningPIDs: [], own: 977, previewState: nil))
    }

    @Test("a frozen preview build runs beside a real one on purpose")
    func previewBuildsRunBeside() {
        #expect(!SingleInstance.shouldYield(runningPIDs: [401, 977], own: 977, previewState: "ready"))
    }
}
