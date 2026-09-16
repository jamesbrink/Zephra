import Foundation
import Testing

@testable import Zephra

@Suite("The script that opens the new Zephra once this one has gone")
struct RelaunchTests {
    @Test("it waits for the process id before it opens anything")
    func waitsForThePid() {
        let script = Relaunch.script(pid: 4321, bundle: URL(filePath: "/Applications/Zephra.app"))
        #expect(script.contains("/bin/kill -0 4321"))
        #expect(script.contains("/bin/sleep"))
        // The wait has to come first: opening while this process lives would be a second copy,
        // which `SingleInstance.yieldToRunningCopy` stands down at once.
        let wait = try! #require(script.range(of: "/bin/kill"))
        let open = try! #require(script.range(of: "/usr/bin/open"))
        #expect(wait.lowerBound < open.lowerBound)
    }

    @Test("a path with a space in it is one word")
    func quotesASpace() {
        let script = Relaunch.script(
            pid: 1, bundle: URL(filePath: "/Users/someone/My Applications/Zephra.app"))
        #expect(script.hasSuffix("'/Users/someone/My Applications/Zephra.app'"))
    }

    @Test("a path with a quote in it cannot end the quoting")
    func quotesAQuote() {
        #expect(Relaunch.quoted("it's") == "'it'\\''s'")
        #expect(Relaunch.quoted("plain") == "'plain'")
        #expect(Relaunch.quoted("a b; rm -rf /") == "'a b; rm -rf /'")
    }
}

/// The latch that keeps two doors from spawning two watcher scripts.
///
/// `Relaunch.afterExit` itself cannot be tested: it spawns a shell and asks the run loop to
/// terminate the process the tests are hosted in. The decision it now takes first is this value,
/// which is why it is one — the rule is provable without a process that has to die to prove it.
@Suite("The one relaunch a launch gets")
struct RelaunchOnceTests {
    @Test("the first ask takes it and every later one is turned away")
    func onlyTheFirstAskWins() {
        var once = RelaunchOnce()
        // Read into values first: `#expect` puts its expression in a closure, where a mutating
        // call on a local is not allowed.
        let button = once.claim()
        // The canvas button at one second and the five-second timer behind it: the second ask
        // must open nothing, or two scripts poll one process id and two copies come back.
        let timer = once.claim()
        let again = once.claim()
        #expect(button)
        #expect(!timer)
        #expect(!again)
    }

    @Test("two launches are two relaunches")
    func eachLaunchGetsItsOwn() {
        var first = RelaunchOnce()
        var second = RelaunchOnce()
        let one = first.claim()
        let other = second.claim()
        #expect(one)
        #expect(other, "the latch is a launch's, not the type's")
    }
}

