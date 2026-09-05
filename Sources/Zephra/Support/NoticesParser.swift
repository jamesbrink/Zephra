import Foundation

/// The line-by-line state behind `NoticesDocument.parse`: which block is open, and what the
/// next line does to it.
///
/// A block stays open until a line says otherwise — a blank line, a heading, a rule, a list
/// marker or a fence — so a paragraph or a list item can run over as many lines as the file
/// wraps it to. Inside a fence nothing is interpreted at all; the only line that means
/// anything there is the closing fence.
nonisolated struct NoticesParser {
    private enum Open {
        case paragraph([String])
        case listItem(indent: Int, lines: [String])
        case code([String])
    }

    private var blocks: [NoticesDocument.Block] = []
    private var open: Open?

    /// Reads one line.
    mutating func take(_ line: String) {
        if case .code(var lines) = open {
            if Self.isFence(line) {
                open = nil
                blocks.append(.code(lines.joined(separator: "\n")))
            } else {
                lines.append(line)
                open = .code(lines)
            }
            return
        }
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        if Self.isFence(line) {
            flush()
            open = .code([])
        } else if trimmed.isEmpty {
            flush()
        } else if let heading = Self.heading(trimmed) {
            flush()
            blocks.append(heading)
        } else if Self.isRule(trimmed) {
            flush()
            blocks.append(.rule)
        } else if trimmed.hasPrefix("- ") {
            flush()
            let indent = line.prefix { $0 == " " }.count >= 2 ? 1 : 0
            open = .listItem(indent: indent, lines: [String(trimmed.dropFirst(2))])
        } else {
            continueOpen(with: trimmed)
        }
    }

    /// Closes whatever is open and hands back every block read.
    mutating func finish() -> [NoticesDocument.Block] {
        flush()
        return blocks
    }

    private mutating func continueOpen(with text: String) {
        switch open {
        case .paragraph(var lines):
            lines.append(text)
            open = .paragraph(lines)
        case .listItem(let indent, var lines):
            lines.append(text)
            open = .listItem(indent: indent, lines: lines)
        case .code, .none:
            open = .paragraph([text])
        }
    }

    private mutating func flush() {
        switch open {
        case .paragraph(let lines):
            blocks.append(.paragraph(lines.joined(separator: " ")))
        case .listItem(let indent, let lines):
            blocks.append(.listItem(text: lines.joined(separator: " "), indent: indent))
        case .code(let lines):
            // A fence the file never closed: what was read is still the text.
            blocks.append(.code(lines.joined(separator: "\n")))
        case .none:
            break
        }
        open = nil
    }

    private static func isFence(_ line: String) -> Bool {
        line.trimmingCharacters(in: .whitespaces).hasPrefix("```")
    }

    /// Three or more dashes and nothing else, which is a rule outside a fence.
    private static func isRule(_ trimmed: String) -> Bool {
        trimmed.count >= 3 && trimmed.allSatisfy { $0 == "-" }
    }

    /// `#`, `##` or `###` followed by a space.
    private static func heading(_ trimmed: String) -> NoticesDocument.Block? {
        let marks = trimmed.prefix { $0 == "#" }
        guard !marks.isEmpty, marks.count <= 6 else { return nil }
        let rest = trimmed.dropFirst(marks.count)
        guard rest.first == " " else { return nil }
        return .heading(level: marks.count, text: rest.trimmingCharacters(in: .whitespaces))
    }
}
