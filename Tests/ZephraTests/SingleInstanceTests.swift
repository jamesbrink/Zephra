import Testing

@testable import Zephra

@Suite("One Zephra at a time")
struct SingleInstanceTests {
    @Test("a launch stands down when another copy of the app is running")
    func standsDownForAnother() {
        #expect(SingleInstance.shouldYield(runningPIDs: [401, 977], own: 977, isolated: false))
    }

    @Test("a launch that finds only itself, or nothing, carries on")
    func carriesOnAlone() {
        #expect(!SingleInstance.shouldYield(runningPIDs: [977], own: 977, isolated: false))
        #expect(!SingleInstance.shouldYield(runningPIDs: [], own: 977, isolated: false))
    }

    @Test("a launch that owns its own library and models folder runs beside a real one")
    func isolatedLaunchesRunBeside() {
        #expect(!SingleInstance.shouldYield(runningPIDs: [401, 977], own: 977, isolated: true))
    }
}
