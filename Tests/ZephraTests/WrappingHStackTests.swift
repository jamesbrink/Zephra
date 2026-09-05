import CoreGraphics
import Testing

@testable import Zephra

@Suite("How a wrapping row breaks its chips into lines")
struct WrappingHStackTests {
    private func chip(_ width: CGFloat, height: CGFloat = 20) -> CGSize {
        CGSize(width: width, height: height)
    }

    @Test("chips that fit stay on one line, with the spacing counted between them")
    func chipsThatFitStayOnOneLine() {
        let rows = WrappingHStack.rows(of: [chip(40), chip(40), chip(40)], within: 140, spacing: 10)
        #expect(rows.count == 1)
        #expect(rows[0].indices == [0, 1, 2])
        #expect(rows[0].width == 140)
    }

    @Test("a chip that would overhang the width starts the next line")
    func overhangStartsTheNextLine() {
        let rows = WrappingHStack.rows(of: [chip(60), chip(60), chip(60)], within: 130, spacing: 10)
        #expect(rows.map(\.indices) == [[0, 1], [2]])
    }

    @Test("a chip wider than the whole line gets a line to itself, not an empty one before it")
    func widerThanTheLineGetsALineToItself() {
        let rows = WrappingHStack.rows(of: [chip(30), chip(300), chip(30)], within: 100, spacing: 6)
        #expect(rows.map(\.indices) == [[0], [1], [2]])
    }

    @Test("a line is as tall as its tallest chip")
    func lineIsAsTallAsItsTallestChip() {
        let sizes = [chip(20, height: 20), chip(20, height: 34), chip(20, height: 10)]
        let rows = WrappingHStack.rows(of: sizes, within: 100, spacing: 0)
        #expect(rows.count == 1)
        #expect(rows[0].height == 34)
    }

    @Test("no chips means no lines")
    func noChipsMeansNoLines() {
        #expect(WrappingHStack.rows(of: [], within: 100, spacing: 6).isEmpty)
    }
}
