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
