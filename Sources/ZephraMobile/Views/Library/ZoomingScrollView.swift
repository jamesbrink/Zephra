import UIKit

/// One picture in a scroll view that zooms, which is how Photos is built and why.
///
/// A `UIScrollView` at zoom 1 has nothing to scroll, so UIKit hands a horizontal pan straight
/// to the pager around it; zoomed in, the same pan scrolls the picture. Nothing here decides
/// which — a SwiftUI drag over the same pixels had to, and got it wrong often enough to feel
/// broken. The image view is sized to the picture's aspect-fitted rectangle and kept in the
/// middle with `contentInset`, so a picture shorter than the screen sits centered at every
/// zoom rather than pinned to the top left corner.
///
/// A double tap goes in to `doubleTapZoom` around the finger, or back to fit; a single tap
/// waits for the double to fail and then reports itself. Both animate unless Reduce Motion is
/// on, and nothing here animates on its own.
final class ZoomingScrollView: UIScrollView, UIScrollViewDelegate {
    /// What a single tap on the picture does.
    var onTap: () -> Void = {}
    /// What a change of "is it zoomed in" does; called on the change, not on every frame.
    var onZoom: (Bool) -> Void = { _ in }

    /// The furthest in anybody may go: past this the pixels are the model's rather than the
    /// picture's, and a phone screen has no more to show.
    static let maximum: CGFloat = 6
    /// Where a double tap lands: enough to read a face or a texture, short of the pixels.
    static let doubleTapZoom: CGFloat = 2.5

    private let imageView = UIImageView()
    /// The bounds the picture was last fitted to, so a rotation refits and a scroll does not.
    private var fittedBounds: CGSize = .zero
    private var wasZoomed = false

    override init(frame: CGRect) {
        super.init(frame: frame)
        delegate = self
        minimumZoomScale = 1
        maximumZoomScale = Self.maximum
        bouncesZoom = true
        showsVerticalScrollIndicator = false
        showsHorizontalScrollIndicator = false
        contentInsetAdjustmentBehavior = .never
        backgroundColor = .clear
        imageView.isAccessibilityElement = true
        imageView.accessibilityLabel = "Picture"
        addSubview(imageView)
        let double = UITapGestureRecognizer(target: self, action: #selector(doubleTapped))
        double.numberOfTapsRequired = 2
        addGestureRecognizer(double)
        let single = UITapGestureRecognizer(target: self, action: #selector(tapped))
        single.require(toFail: double)
        addGestureRecognizer(single)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { nil }

    /// The picture. Replacing it with one of the same shape keeps the zoom, which is what the
    /// viewer does as a thumbnail sharpens into the file; a different shape is fitted afresh.
    var image: UIImage? {
        get { imageView.image }
        set {
            let refit = imageView.image.map { aspect(of: $0) != newValue.map(aspect(of:)) } ?? true
            imageView.image = newValue
            if refit { fittedBounds = .zero }
            setNeedsLayout()
        }
    }

    /// Puts the zoom back to fit at once, for a page that has stopped being the one on screen.
    func resetZoom() {
        guard zoomScale != 1 else { return }
        setZoomScale(1, animated: false)
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        if bounds.size != fittedBounds { fit() }
        center()
    }

    /// Sizes the image view to the picture's aspect-fitted rectangle, at zoom 1.
    private func fit() {
        fittedBounds = bounds.size
        zoomScale = 1
        guard let image = imageView.image, image.size.width > 0, image.size.height > 0,
            bounds.width > 0, bounds.height > 0
        else {
            imageView.frame = .zero
            contentSize = .zero
            return
        }
        let scale = min(bounds.width / image.size.width, bounds.height / image.size.height)
        let size = CGSize(width: image.size.width * scale, height: image.size.height * scale)
        imageView.frame = CGRect(origin: .zero, size: size)
        contentSize = size
    }

    /// Keeps the picture in the middle whenever it is smaller than the screen on an axis.
    private func center() {
        let dx = max(0, (bounds.width - imageView.frame.width) / 2)
        let dy = max(0, (bounds.height - imageView.frame.height) / 2)
        contentInset = UIEdgeInsets(top: dy, left: dx, bottom: dy, right: dx)
    }

    private func aspect(of image: UIImage) -> CGFloat {
        image.size.height > 0 ? image.size.width / image.size.height : 0
    }

    private var animates: Bool { !UIAccessibility.isReduceMotionEnabled }

    @objc private func doubleTapped(_ tap: UITapGestureRecognizer) {
        if zoomScale > 1 {
            setZoomScale(1, animated: animates)
            return
        }
        let point = tap.location(in: imageView)
        let size = CGSize(
            width: bounds.width / Self.doubleTapZoom, height: bounds.height / Self.doubleTapZoom)
        let target = CGRect(
            x: point.x - size.width / 2, y: point.y - size.height / 2,
            width: size.width, height: size.height)
        zoom(to: target, animated: animates)
    }

    @objc private func tapped() { onTap() }

    func viewForZooming(in scrollView: UIScrollView) -> UIView? { imageView }

    func scrollViewDidZoom(_ scrollView: UIScrollView) {
        center()
        let isZoomed = zoomScale > 1.001
        guard isZoomed != wasZoomed else { return }
        wasZoomed = isZoomed
        onZoom(isZoomed)
    }
}
