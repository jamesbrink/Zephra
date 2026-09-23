import AppKit

/// The scroll view a zoomable picture lives in: AppKit's own magnification, so a trackpad
/// pinch zooms about the fingers, a two-finger double tap is smart zoom, and panning has
/// momentum and rubber-banding, as Preview's does.
///
/// Magnification 1 is **fit**: the document view is laid out at the picture's fitted size for
/// the scroll view's current bounds, and laid out again whenever those change, so a resize keeps
/// the picture fitted and a zoomed picture keeps its zoom relative to fit. A new `key` — another
/// picture, a page in the viewer — puts it back at fit.
///
/// At fit it gets out of the way: a mouse click, a right click and a drag are not hit-tested
/// here at all, so they reach the SwiftUI gestures laid on the picture (the canvas's tuck, both
/// right-click menus, the drag-out export, the viewer's double-click), and a scroll that would
/// move nothing goes to the next responder. Zoomed in, a click-drag pans with the grab cursor;
/// a right click still reaches the picture's menu.
final class ZoomScrollView: NSScrollView {
    /// The menu bar's view of this picture, told whenever the zoom moves.
    var zoom: PictureZoom? {
        didSet { zoom?.view = self; report() }
    }

    private let picture = PictureDocumentView()
    private var key: AnyHashable?
    private var laidOutFor: CGSize = .zero

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        contentView = CenteringClipView()
        contentView.postsBoundsChangedNotifications = true
        documentView = picture
        drawsBackground = false
        allowsMagnification = true
        hasHorizontalScroller = true
        hasVerticalScroller = true
        autohidesScrollers = true
        NotificationCenter.default.addObserver(
            self, selector: #selector(boundsMoved), name: NSView.boundsDidChangeNotification,
            object: contentView)
        NotificationCenter.default.addObserver(
            self, selector: #selector(magnifyStarted), name: NSScrollView.willStartLiveMagnifyNotification,
            object: self)
        NotificationCenter.default.addObserver(
            self, selector: #selector(magnifyEnded), name: NSScrollView.didEndLiveMagnifyNotification,
            object: self)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    /// Whether the picture is at fit, where every mouse event belongs to the SwiftUI above.
    var isAtFit: Bool { currentScale.isFit(magnification) }

    /// Shows `image`, back at fit when `key` is not the one already shown.
    func show(_ image: NSImage, hasAlpha: Bool, key: AnyHashable) {
        picture.image = image
        picture.hasAlpha = hasAlpha
        guard key != self.key else { return }
        self.key = key
        laidOutFor = .zero
        layoutPicture()
        magnification = 1
        report()
    }

    /// Zooms to `magnification`, held to what the picture allows, about the middle of what is
    /// on screen.
    func zoom(to magnification: CGFloat) {
        let visible = contentView.bounds
        setMagnification(
            currentScale.clamped(magnification), centeredAt: NSPoint(x: visible.midX, y: visible.midY))
        report()
    }

    override func layout() {
        super.layout()
        layoutPicture()
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        guard let hit = super.hitTest(point) else { return nil }
        guard let event = NSApp.currentEvent else { return hit }
        switch event.type {
        case .rightMouseDown, .rightMouseUp, .rightMouseDragged, .otherMouseDown, .otherMouseUp:
            return nil
        case .leftMouseDown, .leftMouseUp, .leftMouseDragged:
            // Control-click is the right click of a one-button mouse.
            return isAtFit || event.modifierFlags.contains(.control) ? nil : hit
        default:
            return hit
        }
    }

    override func scrollWheel(with event: NSEvent) {
        if isAtFit, !event.modifierFlags.contains(.command) {
            nextResponder?.scrollWheel(with: event)
        } else {
            super.scrollWheel(with: event)
        }
    }

    /// Lays the document out at the fitted size for the bounds this view has now.
    private func layoutPicture() {
        let size = frame.size
        guard size != laidOutFor, let image = picture.image else { return }
        laidOutFor = size
        let pixels = image.pixelSize
        let aspect = pixels.height > 0 ? pixels.width / pixels.height : 1
        let fitted = ZoomScale.fitted(aspect: aspect, in: size)
        picture.frame = NSRect(origin: .zero, size: fitted)
        let scale = ZoomScale(pixels: pixels, fitted: fitted)
        minMagnification = scale.minimum
        maxMagnification = scale.maximum
        currentScale = scale
        report()
    }

    private var currentScale = ZoomScale(pixels: .zero, fitted: .zero)

    @objc private func boundsMoved() { report() }
    @objc private func magnifyStarted() { picture.isMagnifying = true }
    @objc private func magnifyEnded() { picture.isMagnifying = false; report() }

    /// Tells the menu bar, and the cursor, where the zoom is now.
    private func report() {
        documentCursor = isAtFit ? nil : .openHand
        picture.magnification = magnification
        zoom?.report(magnification: magnification, scale: currentScale)
    }
}
