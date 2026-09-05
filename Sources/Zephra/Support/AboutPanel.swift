import AppKit

/// The standard About panel — the app's icon, name, version and copyright, drawn by AppKit —
/// with the third-party notices as its scrolling credits.
///
/// The credits are `NoticesDocument.plainText` rather than a rendering of their own: the
/// panel's credits view is a small text view, and plain text in the small system font is
/// what every Mac About panel puts there. The About tab in Settings draws the same document
/// with `NoticesView`; the two never disagree because they read the one file through the
/// one parser.
@MainActor
enum AboutPanel {
    /// Brings the panel to the front, making it if this is the first time.
    static func show() {
        NSApp.orderFrontStandardAboutPanel(options: [.credits: credits()])
    }

    private static func credits() -> NSAttributedString {
        let style = NSMutableParagraphStyle()
        style.alignment = .left
        return NSAttributedString(
            string: NoticesDocument.bundled().plainText,
            attributes: [
                .font: NSFont.systemFont(ofSize: NSFont.smallSystemFontSize),
                .foregroundColor: NSColor.labelColor,
                .paragraphStyle: style,
            ]
        )
    }
}
