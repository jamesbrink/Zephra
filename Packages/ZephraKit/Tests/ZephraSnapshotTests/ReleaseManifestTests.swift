import Foundation
import Testing

@testable import ZephraSnapshot

@Suite("What the published release manifest says is newer")
struct ReleaseManifestTests {
    private func manifest(build: String) -> ReleaseManifest {
        ReleaseManifest(
            url: URL(string: "https://example.test/releases/Zephra-0.1.0-\(build).dmg")!,
            version: "0.1.0", build: build, sha256: String(repeating: "a", count: 64))
    }

    @Test("a later minute is newer, an earlier one and the same one are not")
    func comparesTheStampAsAWholeNumber() {
        #expect(manifest(build: "202609120231").isNewer(than: "202609112359"))
        #expect(!manifest(build: "202609112359").isNewer(than: "202609120231"))
        #expect(!manifest(build: "202609120231").isNewer(than: "202609120231"))
    }

    @Test("a build that is not a twelve-digit stamp is never newer, in either place")
    func refusesAnythingThatIsNotAStamp() {
        // project.yml's own default, which is what a development build carries.
        #expect(!manifest(build: "202609120231").isNewer(than: "1"))
        #expect(!manifest(build: "1").isNewer(than: "202609112359"))
        #expect(!manifest(build: "20260912023").isNewer(than: "202609112359"))
        #expect(!manifest(build: "2026091202311").isNewer(than: "202609112359"))
        #expect(!manifest(build: "20260912023x").isNewer(than: "202609112359"))
        #expect(!manifest(build: "-02609120231").isNewer(than: "202609112359"))
    }

    @Test("the stamp is digits, and only ASCII ones")
    func spellsAStamp() {
        #expect(ReleaseManifest.isStamp("202609120231"))
        #expect(!ReleaseManifest.isStamp(""))
        #expect(!ReleaseManifest.isStamp("٢٠٢٦٠٩١٢٠٢٣١"))
    }

    @Test("the four fields the publish script writes are the four fields read back")
    func readsWhatThePublishScriptWrote() throws {
        let json = """
            {
              "url": "https://zephra-assets.urandom.io/releases/Zephra-0.1.0-202609120231.dmg",
              "version": "0.1.0",
              "build": "202609120231",
              "sha256": "9f2c1b0e0000000000000000000000000000000000000000000000000000abcd"
            }
            """
        let read = try JSONDecoder().decode(ReleaseManifest.self, from: Data(json.utf8))
        #expect(read.version == "0.1.0")
        #expect(read.build == "202609120231")
        #expect(read.url.lastPathComponent == "Zephra-0.1.0-202609120231.dmg")
        #expect(read.sha256.count == 64)
        #expect(read.line == "Zephra 0.1.0 (build 202609120231)")
    }
}
