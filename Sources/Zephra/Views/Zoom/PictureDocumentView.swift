import AppKit
import SwiftUI
import ZephraCore
import ZephraStyle

/// The picture inside `ZoomScrollView`: drawn to its own bounds with high-quality
/// interpolation, over `Checkerboard`'s squares when it carries alpha, and panned by a
/// click-drag when the scroll view has let the click through — which it does only zoomed in.
///
/// While a pinch is live (`isMagnifying`) it draws cheaply: low interpolation, and the squares
/// are not redrawn at every step, so they scale with the picture until the fingers lift. The
/// pinch's end draws it once more at full quality with the squares back at eight points.
///
/// The squares stay eight points **on screen** at every zoom, as `TransparencyGround`'s do, so
/// the ground reads as the same surface the unzoomed picture sat on rather than as part of the
/// picture growing with it. Their greys are `TransparencyGround`'s own colour sets, resolved for
/// this view's appearance at each draw.
final class PictureDocumentView: NSView {
    /// The pixels.
    var image: NSImage? {
        didSet { if image !== oldValue { needsDisplay = true } }
    }
    /// Whether they carry alpha, and so want the checkerboard behind them.
    var hasAlpha = false {
        didSet { if hasAlpha != oldValue { needsDisplay = true } }
    }
    /// The scroll view's magnification, which the checkerboard's cell is divided by.
    var magnification: CGFloat = 1 {
        didSet { if hasAlpha, !isMagnifying, magnification != oldValue { needsDisplay = true } }
    }
    /// Whether a pinch is under way, which the scroll view says as it starts and ends.
    var isMagnifying = false {
        didSet { if isMagnifying != oldValue { needsDisplay = true } }
    }

    override var isFlipped: Bool { true }
    override var isOpaque: Bool { false }

    override func draw(_ dirtyRect: NSRect) {
        if hasAlpha { drawGround(in: dirtyRect) }
        let quality: NSImageInterpolation = isMagnifying ? .low : .high
        image?.draw(
            in: bounds, from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: true,
            hints: [.interpolation: NSNumber(value: quality.rawValue)])
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        if hasAlpha { needsDisplay = true }
    }

    /// Pans by dragging, in a tracking loop of its own, with the closed hand while it lasts.
    override func mouseDown(with event: NSEvent) {
        guard let scroll = enclosingScrollView, let window else { return }
        NSCursor.closedHand.push()
        defer { NSCursor.pop() }
        while let next = window.nextEvent(matching: [.leftMouseDragged, .leftMouseUp]),
              next.type == .leftMouseDragged
        {
            let clip = scroll.contentView
            var origin = clip.bounds.origin
            origin.x -= next.deltaX / scroll.magnification
            origin.y -= next.deltaY / scroll.magnification
            let proposed = NSRect(origin: origin, size: clip.bounds.size)
            clip.scroll(to: clip.constrainBoundsRect(proposed).origin)
            scroll.reflectScrolledClipView(clip)
        }
    }

    /// The squares under the dirty rectangle, eight points on screen at this magnification.
    private func drawGround(in dirtyRect: NSRect) {
        let rect = dirtyRect.intersection(bounds)
        guard !rect.isEmpty, magnification > 0 else { return }
        let (light, dark) = groundColours()
        light.setFill()
        rect.fill()
        let cell = CGFloat(Checkerboard.cell) / magnification
        let firstColumn = Int(floor(rect.minX / cell)), lastColumn = Int(ceil(rect.maxX / cell))
        let firstRow = Int(floor(rect.minY / cell)), lastRow = Int(ceil(rect.maxY / cell))
        let squares = NSBezierPath()
        for row in firstRow..<max(firstRow, lastRow) {
            for column in firstColumn..<max(firstColumn, lastColumn)
            where !Checkerboard.isLight(x: column, y: row, cell: 1) {
                squares.appendRect(
                    NSRect(x: CGFloat(column) * cell, y: CGFloat(row) * cell, width: cell, height: cell)
                        .intersection(bounds))
            }
        }
        dark.setFill()
        squares.fill()
    }

    /// `TransparencyGround`'s two colour sets, as this view's appearance reads them.
    private func groundColours() -> (NSColor, NSColor) {
        var environment = EnvironmentValues()
        let dark = effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
        environment.colorScheme = dark ? .dark : .light
        return (
            NSColor(Color(Color.transparencyLight.resolve(in: environment))),
            NSColor(Color(Color.transparencyDark.resolve(in: environment)))
        )
    }
}
