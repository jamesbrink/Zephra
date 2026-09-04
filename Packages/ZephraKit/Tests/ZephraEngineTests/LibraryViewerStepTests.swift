import Foundation
import Testing

@testable import ZephraEngine

/// Stepping through the library viewer, across day headings the same way the grid's own arrow
/// keys do.
@Suite("Stepping through the library viewer")
struct LibraryViewerStepTests {
    /// Two days: seven images then three, the same shape `LibraryCursorTests` uses, so a step
    /// crossing the day heading is exercised too.
    static let sections: [LibrarySection] = [
        LibrarySection(day: Date(timeIntervalSince1970: 86_400), items: (0..<7).map { item("a\($0)") }),
        LibrarySection(day: Date(timeIntervalSince1970: 0), items: (0..<3).map { item("b\($0)") }),
    ]

    @Test("next and previous walk the whole grid, day headings and all")
    func nextAndPrevious() {
        #expect(neighbour(.next, of: "a6") == "b0", "over the day heading")
        #expect(neighbour(.previous, of: "b0") == "a6")
        #expect(neighbour(.previous, of: "a0") == nil, "the first image is the end of the line")
        #expect(neighbour(.next, of: "b2") == nil, "and so is the last")
    }

    @Test("an id the grid is not showing has no neighbour and no position")
    func notShown() {
        #expect(LibraryViewerStep.neighbour(of: Self.id("gone"), direction: .next, in: Self.sections) == nil)
        #expect(LibraryViewerStep.position(of: Self.id("gone"), in: Self.sections) == nil)
    }

    @Test("position counts from one, across both days")
    func position() {
        #expect(LibraryViewerStep.position(of: Self.id("a0"), in: Self.sections) == .init(index: 1, count: 10))
        #expect(LibraryViewerStep.position(of: Self.id("a6"), in: Self.sections) == .init(index: 7, count: 10))
        #expect(LibraryViewerStep.position(of: Self.id("b0"), in: Self.sections) == .init(index: 8, count: 10))
        #expect(LibraryViewerStep.position(of: Self.id("b2"), in: Self.sections) == .init(index: 10, count: 10))
    }

    private func neighbour(_ direction: LibraryViewerStep.Direction, of name: String) -> String? {
        LibraryViewerStep.neighbour(of: Self.id(name), direction: direction, in: Self.sections)
            .map(Self.name(of:))
    }

    /// These tests talk in names; an item's identity is its path, so these two translate.
    static func id(_ name: String) -> LibraryItem.ID { "/Zephra/\(name)-0.png" }

    private static func name(of id: LibraryItem.ID) -> String {
        String(URL(filePath: id).deletingPathExtension().lastPathComponent.dropLast(2))
    }

    private static func item(_ name: String) -> LibraryItem {
        LibraryFilteringTests.item(prompt: name, seed: 0)
    }
}
