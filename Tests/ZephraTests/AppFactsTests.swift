import Testing

@testable import Zephra

@Suite("What the About window says about the app")
struct AppFactsTests {
    @Test("the version line is the version with the build in parentheses, and says so when unstamped")
    func versionLine() {
        #expect(AppFacts.versionLine(version: "0.1.0", build: "1") == "Version 0.1.0 (1)")
        #expect(AppFacts.versionLine(version: "0.1.0", build: nil) == "Version 0.1.0")
        #expect(AppFacts.versionLine(version: "0.1.0", build: "") == "Version 0.1.0")
        #expect(AppFacts.versionLine(version: nil, build: "1") == "Development build")
    }

    @Test("the bundle the tests run in carries a version, a copyright and the notices")
    func bundledFacts() {
        #expect(AppFacts.versionLine.hasPrefix("Version "))
        #expect(AppFacts.copyright.contains("Copyright"))
        #expect(AppFacts.summary.contains("Apple Silicon"))
        #expect(!NoticesDocument.bundled().blocks.isEmpty)
    }
}
