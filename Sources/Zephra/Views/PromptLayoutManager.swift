import AppKit

/// Lays the prompt out the way `NSLayoutManager` does, and paints a selection only as far as
/// the text goes.
///
/// A text view highlights a selected line break out to the trailing edge of its container.
/// In a document that is a margin's worth of blue; in the capsule, where the container is the
/// whole width of the prompt area, it was six hundred points of blue after a line of forty
/// characters, and a two-line prompt selected with Command-A looked like a mistake. Xcode
/// stops its highlight at the text, and so does this: every selection rectangle is clipped to
/// the line fragment's used width, with a sliver kept for an empty line so a selected blank
/// line still shows as selected.
///
/// `nonisolated` because `NSLayoutManager` is not a main-actor type and its overrides cannot
/// be; the app target otherwise puts every type on the main actor.
nonisolated final class PromptLayoutManager: NSLayoutManager {
    /// How much of a selected empty line to paint, so it does not vanish.
    private static let sliver: CGFloat = 3

    override func fillBackgroundRectArray(
        _ rectArray: UnsafePointer<NSRect>,
        count rectCount: Int,
        forCharacterRange charRange: NSRange,
        color: NSColor
    ) {
        guard let container = textContainers.first else {
            return super.fillBackgroundRectArray(
                rectArray, count: rectCount, forCharacterRange: charRange, color: color)
        }
        var trimmed = (0..<rectCount).map { rectArray[$0] }
        for index in trimmed.indices {
            var rect = trimmed[index]
            let glyph = glyphIndex(for: NSPoint(x: rect.minX + 1, y: rect.midY), in: container)
            let used = lineFragmentUsedRect(forGlyphAt: glyph, effectiveRange: nil)
            let limit = max(used.maxX, rect.minX + Self.sliver)
            if rect.maxX > limit { rect.size.width = limit - rect.minX }
            trimmed[index] = rect
        }
        trimmed.withUnsafeBufferPointer { buffer in
            guard let base = buffer.baseAddress else { return }
            super.fillBackgroundRectArray(base, count: rectCount, forCharacterRange: charRange, color: color)
        }
    }
}
