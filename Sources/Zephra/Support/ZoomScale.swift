import CoreGraphics

/// How far a zoomable picture may go and where each menu press lands, as magnifications of the
/// picture **fitted** to its pane: 1 is fit, 2 is twice that.
///
/// Pure, so `ZoomScaleTests` pins it without a window. `ZoomScrollView` is what applies it:
/// the scroll view's own `magnification` is this number, because its document view is laid out
/// at the fitted size.
///
/// Actual size is one picture pixel to one point — Preview's Actual Size, and the size a
/// picture is when it is dragged out — rather than one pixel to one device pixel, which on a
/// Retina display would make Actual Size *smaller* than fit for most pictures in most panes.
nonisolated struct ZoomScale: Equatable, Sendable {
    /// The magnification at which the picture is drawn one pixel to a point.
    let actualSize: CGFloat

    /// The deepest zoom anybody may need: eight times fit, or actual size where that is deeper.
    static let deepest: CGFloat = 8

    /// The stops ⌘+ and ⌘− walk between fit and eight times, before actual size is put among
    /// them. Roughly half again each step, as Preview's are.
    static let stops: [CGFloat] = [1, 1.5, 2, 3, 4, 6, 8]

    /// The scale for a picture of `pixels` shown fitted at `fitted` points. A picture with no
    /// size, or laid out at none, has actual size at fit.
    init(pixels: CGSize, fitted: CGSize) {
        guard pixels.width > 0, fitted.width > 0 else {
            actualSize = 1
            return
        }
        actualSize = pixels.width / fitted.width
    }

    /// The shallowest magnification: fit, or actual size for a picture smaller than its pane,
    /// so Actual Size is never a press that does nothing.
    var minimum: CGFloat { min(1, actualSize) }

    /// The deepest magnification: `deepest`, or actual size for a picture so large that one
    /// pixel to a point is past eight times fit.
    var maximum: CGFloat { max(Self.deepest, actualSize) }

    /// Every stop in order, actual size among them.
    var ladder: [CGFloat] {
        var all = Self.stops
        if !all.contains(where: { Self.same($0, actualSize) }) { all.append(actualSize) }
        return all.sorted()
    }

    /// Where Zoom In goes from `current`: the next stop above it, or nil at the deepest.
    func zoomIn(from current: CGFloat) -> CGFloat? {
        ladder.first { $0 > current && !Self.same($0, current) }
    }

    /// Where Zoom Out goes from `current`: the next stop below it, or nil at the shallowest.
    func zoomOut(from current: CGFloat) -> CGFloat? {
        ladder.last { $0 < current && !Self.same($0, current) }
    }

    /// `magnification` held within what this picture allows.
    func clamped(_ magnification: CGFloat) -> CGFloat {
        min(max(magnification, minimum), maximum)
    }

    /// Whether `magnification` is fit, near enough that a pinch settling a hair off counts.
    func isFit(_ magnification: CGFloat) -> Bool { Self.same(magnification, 1) }

    /// Whether `magnification` is actual size, to the same tolerance.
    func isActualSize(_ magnification: CGFloat) -> Bool { Self.same(magnification, actualSize) }

    /// The size a picture of `aspect` (width over height) takes fitted inside `bounds`.
    static func fitted(aspect: CGFloat, in bounds: CGSize) -> CGSize {
        guard aspect > 0, bounds.width > 0, bounds.height > 0 else { return .zero }
        if bounds.width / bounds.height > aspect {
            return CGSize(width: bounds.height * aspect, height: bounds.height)
        }
        return CGSize(width: bounds.width, height: bounds.width / aspect)
    }

    /// Two magnifications within half a percent of each other are the same stop.
    private static func same(_ a: CGFloat, _ b: CGFloat) -> Bool { abs(a - b) < 0.005 }
}
