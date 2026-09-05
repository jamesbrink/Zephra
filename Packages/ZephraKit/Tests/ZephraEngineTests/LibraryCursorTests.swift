import Foundation
import Testing

@testable import ZephraEngine

/// Arrow keys and clicks over a grid split into days.
@Suite("Moving the selection around the library grid")
struct LibraryCursorTests {
    /// Two days: seven images then three, which is what makes the column clamp worth testing.
    static let sections: [LibrarySection] = [
        LibrarySection(day: Date(timeIntervalSince1970: 86_400), items: (0..<7).map { item("a\($0)") }),
        LibrarySection(day: Date(timeIntervalSince1970: 0), items: (0..<3).map { item("b\($0)") }),
    ]

    @Test("left and right walk the whole grid, day headings and all")
    func leftAndRight() {
        #expect(Self.moved(.right, from: "a6") == "b0", "over the day heading")
        #expect(Self.moved(.left, from: "b0") == "a6")
        #expect(Self.move(.left, from: "a0") == nil, "the first image is the end of the line")
        #expect(Self.move(.right, from: "b2") == nil)
        #expect(Self.moved(.home, from: "b2") == "a0")
        #expect(Self.moved(.end, from: "a0") == "b2")
        #expect(Self.moved(.right, from: nil) == "a0", "with nothing selected, start at the start")
        #expect(Self.moved(.up, from: nil) == "b2")
    }

    @Test("up and down move by a row, and step into the next day at the same column")
    func upAndDown() {
        #expect(Self.moved(.down, from: "a0") == "a4", "four columns")
        #expect(Self.moved(.up, from: "a4") == "a0")
        // The second row of the first day is a4, a5, a6: down from a5 lands in the day below.
        #expect(Self.moved(.down, from: "a5") == "b1")
        #expect(Self.moved(.up, from: "b1") == "a5")
        // Column 3 does not exist in a day of three, so it clamps to the last of them.
        #expect(Self.moved(.down, from: "a3") == "b2")
        #expect(Self.moved(.up, from: "b2") == "a6", "and back to the last row above")
        #expect(Self.move(.up, from: "a1") == nil, "the top row has nowhere to go")
        #expect(Self.move(.down, from: "b0") == nil)
    }

    @Test("holding shift keeps the anchor put, so the run grows and shrinks the same way")
    func extending() throws {
        let first = try #require(Self.extend(.right, selection: Self.ids("a0"), anchor: "a0"))
        #expect(first.ids == Self.ids("a0", "a1"))
        #expect(first.anchor == Self.id("a0"), "the anchor is where it was")
        #expect(first.reveal == Self.id("a1"), "and the cursor is where it went")

        let second = try #require(
            Self.extend(.right, selection: first.ids, anchor: "a0"))
        #expect(second.ids == Self.ids("a0", "a1", "a2"))
        let third = try #require(Self.extend(.right, selection: second.ids, anchor: "a0"))
        #expect(third.ids == Self.ids("a0", "a1", "a2", "a3"))

        // Coming back takes the run back with it, rather than leaving what was swept behind.
        let back = try #require(Self.extend(.left, selection: third.ids, anchor: "a0"))
        #expect(back.ids == Self.ids("a0", "a1", "a2"))
        #expect(back.anchor == Self.id("a0"))
        #expect(back.reveal == Self.id("a2"))
    }

    @Test("shift also extends backwards, from an anchor at the far end")
    func extendingBackwards() throws {
        let up = try #require(Self.extend(.up, selection: Self.ids("b1"), anchor: "b1"))
        #expect(up.ids == Self.ids("a5", "a6", "b0", "b1"))
        #expect(up.anchor == Self.id("b1"))
        #expect(up.reveal == Self.id("a5"))

        let down = try #require(Self.extend(.down, selection: up.ids, anchor: "b1"))
        #expect(down.ids == Self.ids("b1"), "back down to the anchor")
    }

    @Test("a plain click replaces, command adds and removes, shift takes the run between")
    func clicks() {
        let plain = LibraryCursor.click(
            Self.id("a3"), in: Self.sections, modifiers: [], selection: Self.ids("a0", "a1"),
            anchor: Self.id("a0"))
        #expect(plain.ids == Self.ids("a3"))
        #expect(plain.anchor == Self.id("a3"))
        #expect(plain.reveal == nil, "a click is on something already on screen")

        let added = LibraryCursor.click(
            Self.id("a5"), in: Self.sections, modifiers: .command, selection: Self.ids("a3"),
            anchor: Self.id("a3"))
        #expect(added.ids == Self.ids("a3", "a5"))
        let removed = LibraryCursor.click(
            Self.id("a5"), in: Self.sections, modifiers: .command, selection: added.ids,
            anchor: Self.id("a5"))
        #expect(removed.ids == Self.ids("a3"))

        let run = LibraryCursor.click(
            Self.id("b0"), in: Self.sections, modifiers: .shift, selection: Self.ids("a6"),
            anchor: Self.id("a6"))
        #expect(run.ids == Self.ids("a6", "b0"))
        #expect(run.anchor == Self.id("a6"), "shift leaves the anchor where it was")

        let both = LibraryCursor.click(
            Self.id("b2"), in: Self.sections, modifiers: [.shift, .command],
            selection: Self.ids("a0"), anchor: Self.id("b1"))
        #expect(both.ids == Self.ids("a0", "b1", "b2"))
    }

    @Test("one section with no headings moves by the column count, as the reference picker's grid does")
    func flatGrid() {
        let flat = [LibrarySection(day: .distantPast, items: (0..<7).map { Self.item("a\($0)") })]
        func move(_ direction: LibraryCursor.Direction, from name: String?) -> LibraryItem.ID? {
            let anchor = name.map(Self.id)
            return LibraryCursor.move(
                direction, in: flat, columns: 3, selection: anchor.map { [$0] } ?? [], anchor: anchor
            )?.reveal
        }
        #expect(move(.down, from: "a1") == Self.id("a4"), "three columns")
        #expect(move(.up, from: "a4") == Self.id("a1"))
        #expect(move(.down, from: "a5") == nil, "the last row has nowhere to go")
        #expect(move(.right, from: "a6") == nil)
        #expect(move(.down, from: nil) == Self.id("a0"), "with nothing picked, the first arrow picks the first")
        #expect(move(.left, from: nil) == Self.id("a6"), "or the last, coming from that end")
    }

    @Test("select all takes everything on screen, and an empty grid moves nowhere")
    func selectAllAndEmptyGrids() {
        let all = LibraryCursor.selectAll(in: Self.sections)
        #expect(all.ids.count == 10)
        #expect(all.anchor == Self.id("a0"))

        #expect(LibraryCursor.selectAll(in: []).ids.isEmpty)
        #expect(LibraryCursor.move(.down, in: [], columns: 4, selection: [], anchor: nil) == nil)
    }

    @MainActor
    @Test("the selection adopts an outcome, and drops what is no longer on screen")
    func selectionFollowsTheGrid() {
        let selection = LibrarySelection()
        selection.apply(LibraryCursor.selectAll(in: Self.sections))
        #expect(selection.count == 10)
        #expect(selection.single == nil)
        #expect(selection.contains(Self.id("b2")))

        selection.keeping(Self.ids("a0", "a1"))
        #expect(selection.ids == Self.ids("a0", "a1"))
        #expect(selection.anchor == Self.id("a0"), "the anchor is still on screen")

        selection.keeping(Self.ids("a1"))
        #expect(selection.single == Self.id("a1"))
        #expect(selection.anchor == Self.id("a1"), "and follows the selection when it is not")

        selection.clear()
        #expect(selection.ids.isEmpty)
        #expect(selection.anchor == nil)
    }

    /// These tests talk in names; an item's identity is its path, so these two translate.
    static func id(_ name: String) -> LibraryItem.ID { "/Zephra/\(name)-0.png" }

    static func ids(_ names: String...) -> Set<LibraryItem.ID> { Set(names.map(id)) }

    private static func name(of id: LibraryItem.ID) -> String {
        String(URL(filePath: id).deletingPathExtension().lastPathComponent.dropLast(2))
    }

    private static func extend(
        _ direction: LibraryCursor.Direction,
        selection: Set<LibraryItem.ID>,
        anchor: String
    ) -> LibraryCursor.Outcome? {
        LibraryCursor.move(
            direction, in: sections, columns: 4, selection: selection, anchor: id(anchor),
            extending: true)
    }

    private static func move(_ direction: LibraryCursor.Direction, from name: String?)
        -> LibraryCursor.Outcome?
    {
        let anchor = name.map(id)
        return LibraryCursor.move(
            direction, in: sections, columns: 4, selection: anchor.map { [$0] } ?? [],
            anchor: anchor)
    }

    private static func moved(_ direction: LibraryCursor.Direction, from name: String?) -> String? {
        move(direction, from: name)?.anchor.map(Self.name(of:))
    }

    private static func item(_ name: String) -> LibraryItem {
        LibraryFilteringTests.item(prompt: name, seed: 0)
    }
}
