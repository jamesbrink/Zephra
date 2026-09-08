import Testing

@testable import Zephra

@Suite("Reading the third-party notices as a document")
struct NoticesDocumentTests {
    private static let sample = """
        # Third-Party Notices

        Zephra incorporates the following
        components.

        ## Components

        ### mlx-swift

        - **Source:** https://github.com/ml-explore/mlx-swift
        - **Used as:** the runtime, a dependency
          of `ZImageKit`. It compiles:
          - **mlx** — MIT

        ---

        ```
        MIT License
           indented line kept
        ```
        """

    @Test("headings come out by level, with their marks gone")
    func headingsByLevel() {
        let document = NoticesDocument.parse(Self.sample)
        #expect(document.blocks[0] == .heading(level: 1, text: "Third-Party Notices"))
        #expect(document.blocks.contains(.heading(level: 2, text: "Components")))
        #expect(document.blocks.contains(.heading(level: 3, text: "mlx-swift")))
    }

    @Test("a paragraph wrapped over two lines is one block, and a list item with a continuation line is one item")
    func wrappedLinesJoin() {
        let document = NoticesDocument.parse(Self.sample)
        #expect(document.blocks[1] == .paragraph("Zephra incorporates the following components."))
        #expect(document.blocks.contains(
            .listItem(text: "**Used as:** the runtime, a dependency of `ZImageKit`. It compiles:", indent: 0)))
    }

    @Test("an item indented under another is nested one level")
    func nestedItems() {
        let document = NoticesDocument.parse(Self.sample)
        #expect(document.blocks.contains(.listItem(text: "**mlx** — MIT", indent: 1)))
    }

    @Test("a fence keeps its lines exactly, indentation included, and a line of dashes is a rule")
    func fencesAreVerbatim() {
        let document = NoticesDocument.parse(Self.sample)
        #expect(document.blocks.contains(.rule))
        #expect(document.blocks.last == .code("MIT License\n   indented line kept"))
    }

    @Test("backticks and bold survive in the block text for the renderer")
    func inlineMarksSurvive() {
        let document = NoticesDocument.parse("- **Source:** `Packages/ZImageKit`")
        #expect(document.blocks == [.listItem(text: "**Source:** `Packages/ZImageKit`", indent: 0)])
    }

    @Test("a heading mark without a space after it is text, not a heading")
    func hashWithoutSpaceIsText() {
        let document = NoticesDocument.parse("#hashtag")
        #expect(document.blocks == [.paragraph("#hashtag")])
    }

    @Test("the notices bundled with the app parse to headings, items and a license text")
    func bundledNoticesParse() {
        let document = NoticesDocument.bundled()
        #expect(document.blocks.first == .heading(level: 1, text: "Third-Party Notices"))
        #expect(document.blocks.contains { if case .listItem = $0 { true } else { false } })
        #expect(document.blocks.contains { if case .code = $0 { true } else { false } })
    }
}
