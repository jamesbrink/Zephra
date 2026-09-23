import AppKit

/// A clip view that keeps a picture smaller than the pane in the middle of it, rather than in
/// the corner AppKit's own clip view pins a small document to — which is where a picture fitted
/// to a wide pane, or zoomed out below fit, would otherwise sit.
final class CenteringClipView: NSClipView {
    override func constrainBoundsRect(_ proposedBounds: NSRect) -> NSRect {
        var rect = super.constrainBoundsRect(proposedBounds)
        guard let document = documentView?.frame else { return rect }
        if rect.width > document.width {
            rect.origin.x = document.minX - (rect.width - document.width) / 2
        }
        if rect.height > document.height {
            rect.origin.y = document.minY - (rect.height - document.height) / 2
        }
        return rect
    }
}
