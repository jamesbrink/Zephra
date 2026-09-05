import Foundation

/// `THIRD_PARTY_NOTICES.md` read as blocks, so it can be laid out rather than shown raw.
///
/// The file is the disclosure, so nothing here rewrites it: the parser only says where one
/// block ends and the next begins, and what kind each is. One parser, two renderers —
/// `NoticesView` draws the blocks in the About tab, and `plainText` is what the standard
/// About panel takes as its credits, which is plain text on purpose.
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

    /// The document with its Markdown syntax gone: headings on their own line in capitals,
    /// list items bulleted and indented, code verbatim, and a blank line between blocks.
    var plainText: String {
        var lines: [String] = []
        for block in blocks {
            switch block {
            case .heading(_, let text):
                lines.append(Self.stripped(text).uppercased())
            case .listItem(let text, let indent):
                lines.append(String(repeating: "    ", count: indent) + "\u{2022} " + Self.stripped(text))
            case .paragraph(let text):
                lines.append(Self.stripped(text))
            case .code(let text):
                lines.append(text)
            case .rule:
                continue
            }
            lines.append("")
        }
        return lines.joined(separator: "\n").trimmingCharacters(in: .newlines)
    }

    /// The text without its inline marks: the `**` round a bold run and the backticks round
    /// code. Nothing else is used inline in the file.
    static func stripped(_ text: String) -> String {
        text.replacingOccurrences(of: "**", with: "").replacingOccurrences(of: "`", with: "")
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
