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

    @Test("two directories keep two sets of preferences, and one directory keeps one")
    func eachDirectoryKeepsItsOwnPreferences() throws {
        // One domain for every fresh start meant the second launch opened on the first's
        // answers: its chooser already answered, its model already chosen, which is not a Mac
        // that has never run Zephra.
        let one = try #require(FreshStart.resolve(["ZEPHRA_FRESH_START": "/tmp/fresh-one"]))
        let two = try #require(FreshStart.resolve(["ZEPHRA_FRESH_START": "/tmp/fresh-two"]))
        #expect(one.defaultsSuite != two.defaultsSuite)

        // The same directory, spelled three ways and resolved twice, is one domain: the name
        // has to survive a relaunch or nothing a fresh start remembers would.
        let again = try #require(FreshStart.resolve(["ZEPHRA_FRESH_START": "/tmp/fresh-one"]))
        let slashed = try #require(FreshStart.resolve(["ZEPHRA_FRESH_START": "/tmp/fresh-one/"]))
        let winding = try #require(FreshStart.resolve(["ZEPHRA_FRESH_START": "/tmp/./fresh-one"]))
        #expect(one.defaultsSuite == again.defaultsSuite)
        #expect(one.defaultsSuite == slashed.defaultsSuite)
        #expect(one.defaultsSuite == winding.defaultsSuite)
    }

    @Test("a directory never launched before opens on empty preferences, and keeps them after")
    func aNewDirectoryStartsEmpty() throws {
        let root = URL.temporaryDirectory.appending(path: "zephra-fresh-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        let fresh = FreshStart(root: root)
        defer { UserDefaults().removePersistentDomain(forName: fresh.defaultsSuite) }

        let first = try #require(fresh.preferences())
        first.set("a prompt from an older launch", forKey: AppSettings.lastPrompt)

        // The directory is still there, stamp and all, so this is the same session resumed.
        #expect(try #require(fresh.preferences()).string(forKey: AppSettings.lastPrompt) != nil)

        // `FRESH_RESET=1` is an `rm -rf` of the directory; the answers have to go with it.
        try FileManager.default.removeItem(at: root)
        #expect(try #require(fresh.preferences()).string(forKey: AppSettings.lastPrompt) == nil)
        #expect(FileManager.default.fileExists(atPath: fresh.suiteStamp.path(percentEncoded: false)))
    }

    @Test("the preferences domain is not the one a person's own launch reads")
    func itsOwnPreferencesDomain() throws {
        let fresh = try #require(FreshStart.resolve(["ZEPHRA_FRESH_START": "/tmp/fresh"]))
        #expect(fresh.defaultsSuite != Bundle.main.bundleIdentifier)
        #expect(fresh.defaultsSuite.hasPrefix(FreshStart.suitePrefix))
        #expect(fresh.defaultsSuite != FreshStart.suitePrefix)
        // These tests run under `ZEPHRA_PREVIEW_STATE`, never a fresh start, so the store the
        // app reads is the standard one; a fresh launch is what swaps it.
        #expect(FreshStart.current == nil)
        #expect(AppSettings.store == UserDefaults.standard)
    }
}
