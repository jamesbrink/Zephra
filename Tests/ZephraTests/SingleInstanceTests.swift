import Testing
import ZephraEngine

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

    // What used to feed `isolated:` above was `InterfacePreview.name != nil`, the raw
    // environment variable. `requestedState` is the field that is actually `#if DEBUG`, and
    // these pin the predicate that reads it — the bug was in how the boolean at the call site
    // was computed, which `shouldYield`'s own tests, above, cannot see since they take the
    // boolean already made.

    @Test("a frozen preview build is isolated, whatever state it asked for")
    func previewStateIsolates() {
        #expect(SingleInstance.isolated(previewState: .ready, freshStart: nil))
    }

    @Test("a fresh start is isolated, with no preview state at all")
    func freshStartIsolates() {
        let freshStart = FreshStart.resolve(["ZEPHRA_FRESH_START": "/tmp/zephra-fresh"])
        #expect(SingleInstance.isolated(previewState: nil, freshStart: freshStart))
    }

    @Test("an ordinary launch, neither previewed nor fresh, is not isolated")
    func ordinaryLaunchIsNotIsolated() {
        #expect(!SingleInstance.isolated(previewState: nil, freshStart: nil))
    }
}
