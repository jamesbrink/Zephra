import SwiftUI

/// The third-party notices laid out as a document: headings stepped down by level, list
/// items bulleted with a hanging indent, prose in the caption size, and the NOTICE file and
/// license texts in a monospaced face, as they are written.
///
/// Every line is selectable, because the notices are the thing a person may need to quote.
struct NoticesView: View {
    /// The parsed document.
    let document: NoticesDocument

    var body: some View {
        LazyVStack(alignment: .leading, spacing: 8) {
            ForEach(Array(document.blocks.enumerated()), id: \.offset) { _, block in
                view(for: block)
            }
        }
        .textSelection(.enabled)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private func view(for block: NoticesDocument.Block) -> some View {
        switch block {
        case .heading(let level, let text):
            inline(text)
                .font(Self.headingFont(level))
                .padding(.top, level == 1 ? 0 : 8)
        case .listItem(let text, let indent):
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text("\u{2022}")
                inline(text)
            }
            .font(.caption)
            .padding(.leading, CGFloat(indent) * 16)
        case .paragraph(let text):
            inline(text)
                .font(.caption)
        case .code(let text):
            Text(verbatim: text)
                .font(.caption)
                .monospaced()
                .padding(.vertical, 4)
        case .rule:
            Divider()
        }
    }

    /// Bold and code inside a line, as the file marks them; a line the parser cannot read
    /// as Markdown is shown as it is rather than dropped.
    private func inline(_ text: String) -> Text {
        let options = AttributedString.MarkdownParsingOptions(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        if let attributed = try? AttributedString(markdown: text, options: options) {
            return Text(attributed)
        }
        return Text(verbatim: text)
    }

    private static func headingFont(_ level: Int) -> Font {
        switch level {
        case 1: .headline
        case 2: .subheadline.bold()
        default: .callout.bold()
        }
    }
}

#Preview("Notices") {
    ScrollView {
        NoticesView(document: NoticesDocument.parse("""
        # Third-Party Notices

        Zephra incorporates the following components, each under its own license.

        ## Components

        ### mlx-swift

        - **Source:** https://github.com/ml-explore/mlx-swift
        - **Used as:** the runtime every pipeline is built on. It compiles the following
          into the same binary:
          - **mlx** — Copyright © 2023 Apple Inc. — MIT

        ---

        ### MIT License

        ```
        Permission is hereby granted, free of charge, to any person obtaining a copy
        of this software.
        ```
        """))
        .padding(18)
    }
    .frame(width: 480, height: 420)
}
