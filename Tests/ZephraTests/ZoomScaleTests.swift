import CoreGraphics
import Testing

@testable import Zephra

@Suite("How far a picture zooms and where each press lands")
struct ZoomScaleTests {
    @Test("actual size is the picture's pixels over the points it is fitted to")
    func actualSizeIsPixelsOverFittedPoints() {
        let scale = ZoomScale(pixels: CGSize(width: 1024, height: 1024), fitted: CGSize(width: 512, height: 512))
        #expect(scale.actualSize == 2)
    }

    @Test("fit is the floor and eight times is the ceiling for an ordinary picture")
    func fitToEight() {
        let scale = ZoomScale(pixels: CGSize(width: 1024, height: 768), fitted: CGSize(width: 800, height: 600))
        #expect(scale.minimum == 1)
        #expect(scale.maximum == 8)
        #expect(scale.clamped(20) == 8)
        #expect(scale.clamped(0.2) == 1)
    }

    @Test("a picture larger than eight fits still reaches actual size")
    func hugePictureReachesActualSize() {
        let scale = ZoomScale(pixels: CGSize(width: 10_000, height: 10_000), fitted: CGSize(width: 500, height: 500))
        #expect(scale.maximum == 20)
        #expect(scale.ladder.last == 20)
    }

    @Test("a picture smaller than its pane can go down to actual size, so the press does something")
    func smallPictureGoesBelowFit() {
        let scale = ZoomScale(pixels: CGSize(width: 256, height: 256), fitted: CGSize(width: 512, height: 512))
        #expect(scale.minimum == 0.5)
        #expect(scale.ladder.first == 0.5)
        #expect(scale.zoomOut(from: 1) == 0.5)
    }

    @Test("Zoom In and Zoom Out walk the ladder with actual size among the stops")
    func walksTheLadder() {
        let scale = ZoomScale(pixels: CGSize(width: 1250, height: 1250), fitted: CGSize(width: 500, height: 500))
        #expect(scale.ladder == [1, 1.5, 2, 2.5, 3, 4, 6, 8])
        var steps: [CGFloat] = []
        var current: CGFloat = 1
        while let next = scale.zoomIn(from: current) {
            steps.append(next)
            current = next
        }
        #expect(steps == [1.5, 2, 2.5, 3, 4, 6, 8])
        #expect(scale.zoomIn(from: 8) == nil)
        #expect(scale.zoomOut(from: 8) == 6)
        #expect(scale.zoomOut(from: 1) == nil)
    }

    @Test("a magnification between stops goes to the neighbouring stop, and a hair off a stop counts as on it")
    func betweenStops() {
        let scale = ZoomScale(pixels: CGSize(width: 1000, height: 1000), fitted: CGSize(width: 1000, height: 1000))
        #expect(scale.zoomIn(from: 1.7) == 2)
        #expect(scale.zoomOut(from: 1.7) == 1.5)
        #expect(scale.zoomIn(from: 1.999) == 3)
        #expect(scale.isFit(1.001))
        #expect(scale.isActualSize(1))
    }

    @Test("a picture with no size has actual size at fit")
    func noSize() {
        #expect(ZoomScale(pixels: .zero, fitted: CGSize(width: 10, height: 10)).actualSize == 1)
        #expect(ZoomScale(pixels: CGSize(width: 10, height: 10), fitted: .zero).actualSize == 1)
    }

    @Test("fitting keeps the aspect and touches two edges")
    func fitting() {
        #expect(ZoomScale.fitted(aspect: 2, in: CGSize(width: 800, height: 600)) == CGSize(width: 800, height: 400))
        #expect(ZoomScale.fitted(aspect: 0.5, in: CGSize(width: 800, height: 600)) == CGSize(width: 300, height: 600))
        #expect(ZoomScale.fitted(aspect: 1, in: .zero) == .zero)
    }
}
