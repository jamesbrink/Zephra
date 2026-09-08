import Foundation
import Testing

@testable import Zephra

@Suite("A launch pretending this Mac has never run Zephra")
struct FreshStartTests {
    @Test("the directory named in the environment is what everything the launch keeps hangs off")
    func theDirectoryIsTheRoot() throws {
        let fresh = try #require(FreshStart.resolve(["ZEPHRA_FRESH_START": "/tmp/fresh"]))
        #expect(fresh.root.path(percentEncoded: false) == "/tmp/fresh/")
        #expect(fresh.models.path(percentEncoded: false) == "/tmp/fresh/Models/")
        #expect(fresh.images.path(percentEncoded: false) == "/tmp/fresh/Images/")
    }

    @Test("an ordinary launch asks for none, and neither does an empty path")
    func anOrdinaryLaunchHasNone() {
        #expect(FreshStart.resolve([:]) == nil)
        #expect(FreshStart.resolve(["ZEPHRA_FRESH_START": ""]) == nil)
    }

    @Test("the preferences domain is not the one a person's own launch reads")
    func itsOwnPreferencesDomain() {
        #expect(FreshStart.defaultsSuite != Bundle.main.bundleIdentifier)
        // These tests run under `ZEPHRA_PREVIEW_STATE`, never a fresh start, so the store the
        // app reads is the standard one; a fresh launch is what swaps it.
        #expect(FreshStart.current == nil)
        #expect(AppSettings.store == UserDefaults.standard)
    }
}
