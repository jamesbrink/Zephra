import Foundation
import Testing
import ZephraCore

@testable import ZephraEngine

@Suite("The recent prompts on the empty canvas")
struct RecentPromptsTests {
    @Test("duplicates collapse to the newest spelling, whatever the case or the spaces")
    func duplicatesCollapse() {
        let items = [
            Fixtures.item(prompt: "A Lighthouse at dusk", at: 30),
            Fixtures.item(prompt: "a red bicycle", at: 20),
            Fixtures.item(prompt: "  a lighthouse at dusk ", at: 10),
        ]
        #expect(RecentPrompts.from(items, excluding: "") == ["A Lighthouse at dusk", "a red bicycle"])
    }

    @Test("the prompt already in the field is left out, and so are blanks")
    func currentAndBlanksAreLeftOut() {
        let items = [
            Fixtures.item(prompt: "a red bicycle", at: 30),
            Fixtures.item(prompt: "   ", at: 20),
            Fixtures.item(prompt: "a lighthouse at dusk", at: 10),
        ]
        #expect(RecentPrompts.from(items, excluding: "A red bicycle ") == ["a lighthouse at dusk"])
    }

    @Test("the limit holds and the order is the index's")
    func limitHolds() {
        let items = (0..<6).map { Fixtures.item(prompt: "prompt \($0)", at: TimeInterval(60 - $0)) }
        #expect(RecentPrompts.from(items, excluding: "", limit: 3) == ["prompt 0", "prompt 1", "prompt 2"])
        #expect(RecentPrompts.from([], excluding: "").isEmpty)
    }
}
