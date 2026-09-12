import Foundation
import Testing
import ZephraSnapshot

@testable import Zephra

@Suite("The two switches the updater reads once at launch")
struct UpdateEnvironmentTests {
    @Test("nothing set is the published feed and this build's own number")
    func defaultsToTheProductionFeed() {
        let read = UpdateEnvironment.read([:])
        #expect(read.feed == UpdateFeed.production)
        #expect(read.pretendBuild == nil)
        #expect(!read.isOverridden)
    }

    @Test("a feed and a build stamp are both taken, and either one is an override")
    func readsBothSwitches() {
        let read = UpdateEnvironment.read([
            UpdateEnvironment.feedVariable: "http://127.0.0.1:8000/releases/latest.json",
            UpdateEnvironment.buildVariable: "202601010000",
        ])
        #expect(read.feed.absoluteString == "http://127.0.0.1:8000/releases/latest.json")
        #expect(read.pretendBuild == "202601010000")
        #expect(read.isOverridden)
        #expect(UpdateEnvironment.read([UpdateEnvironment.buildVariable: "202601010000"]).isOverridden)
    }

    @Test("a value that is not a URL, or an empty one, is ignored rather than fatal")
    func ignoresWhatItCannotRead() {
        let read = UpdateEnvironment.read([
            UpdateEnvironment.feedVariable: "not a url at all",
            UpdateEnvironment.buildVariable: "",
        ])
        #expect(read.feed == UpdateFeed.production)
        #expect(read.pretendBuild == nil)
    }

    @Test("the build compared is the pretended one when there is one")
    func pretendingAnOlderBuild() {
        #expect(RunningBuild.number(pretending: "202601010000") == "202601010000")
        #expect(RunningBuild.number(pretending: "") == RunningBuild.number())
    }
}
