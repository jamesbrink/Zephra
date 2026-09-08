import Foundation

/// `THIRD_PARTY_NOTICES.md` read as blocks, so it can be laid out rather than shown raw.
///
/// The file is the disclosure, so nothing here rewrites it: the parser only says where one
/// block ends and the next begins, and what kind each is; `NoticesView` draws the blocks in
/// the Acknowledgments window.
///
/// The subset of Markdown read is exactly what the file uses: `#` headings, `- ` list items
/// (nested one level, continued on indented lines), paragraphs separated by blank lines,
/// `---` rules, and fenced code blocks, which is how the file marks the NOTICE file and the
/// license texts as preformatted. Inline bold and code are left in the text for the renderer.
nonisolated struct NoticesDocument: Equatable, Sendable {
    /// One block of the document, in the order written.
    enum Block: Equatable, Sendable {
        /// A `#` heading; the level is how many.
        case heading(level: Int, text: String)
        /// A `- ` item, with its continuation lines joined; `indent` is 0 at the margin and
        /// 1 for an item nested under another.
        case listItem(text: String, indent: Int)
        /// Consecutive lines of prose, joined by spaces.
        case paragraph(String)
        /// The lines between a pair of fences, verbatim: a NOTICE file or a license text.
        case code(String)
        /// A `---` line.
        case rule
    }

    let blocks: [Block]

    /// Reads the document from its Markdown.
    static func parse(_ markdown: String) -> NoticesDocument {
        var parser = NoticesParser()
        for line in markdown.split(separator: "\n", omittingEmptySubsequences: false) {
            parser.take(String(line))
        }
        return NoticesDocument(blocks: parser.finish())
    }

    /// The notices bundled with the app, parsed; or one paragraph saying where they are
    /// when a build has left the file out.
    static func bundled() -> NoticesDocument {
        guard let url = Bundle.main.url(forResource: "THIRD_PARTY_NOTICES", withExtension: "md"),
              let text = try? String(contentsOf: url, encoding: .utf8)
        else {
            return NoticesDocument(blocks: [
                .paragraph("Acknowledgements are in THIRD_PARTY_NOTICES.md in the source repository."),
            ])
        }
        return parse(text)
    }
}
