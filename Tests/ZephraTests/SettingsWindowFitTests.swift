import CoreGraphics
import Testing

@testable import Zephra

@Suite("How big the Settings window may be on this display")
struct SettingsWindowFitTests {
    /// A 1728 x 1080-point display: 1056 points left under the 24-point menu bar, and 88 points
    /// of window chrome (32 title bar, 56 tab strip).
    private let visible: CGFloat = 1056
    private let chrome: CGFloat = 88
    private let floor: CGFloat = 400

    private func fit(_ height: CGFloat, visible: CGFloat? = nil) -> CGSize {
        SettingsWindowFit.contentSize(
            opening: CGSize(width: 520, height: height), chromeHeight: chrome,
            visibleHeight: visible ?? self.visible, floor: floor)
    }

    @Test("a tab the display has room for opens at its own height")
    func aShortTabIsUntouched() {
        #expect(fit(560).height == 560)
    }

    @Test("Performance on a 1080-point display opens at what is left, not at its own 1010")
    func performanceIsClampedToTheDisplay() {
        #expect(fit(1010).height == 968)
    }

    @Test("a display too small for the floor still gets the floor")
    func theFloorWinsOverATinyDisplay() {
        #expect(fit(1010, visible: 300).height == floor)
        #expect(fit(560, visible: 300).height == floor)
    }

    @Test("the width is the tab's own whatever the display has")
    func theWidthIsNeverTouched() {
        #expect(fit(1010).width == 520)
        #expect(fit(1010, visible: 300).width == 520)
    }

    @Test("a tab switch grows a window that is shorter than the clamped target")
    func aShorterWindowGrowsToTheTarget() {
        let grown = SettingsWindowFit.grown(
            current: CGSize(width: 520, height: 560), toward: fit(1010))
        #expect(grown.height == 968)
    }

    @Test("a tab switch never shrinks a window the person made taller")
    func aTallerWindowKeepsItsSize() {
        let grown = SettingsWindowFit.grown(
            current: CGSize(width: 700, height: 1000), toward: fit(560))
        #expect(grown.height == 1000)
        #expect(grown.width == 700)
    }

    /// The workstation display the bug was reported from: 1728 x 1117 points, 1010 of them
    /// left between the menu bar and the Dock.
    private let screen = CGRect(x: 0, y: 74, width: 1728, height: 1010)

    @Test("a window grown off the bottom of the display is moved back on")
    func aGrownWindowIsPutBackOnTheScreen() {
        // Where the Settings window stood after growing onto Performance: 1010 points of frame
        // from a bottom edge 39 points below the visible frame.
        let placed = SettingsWindowFit.placed(
            CGRect(x: 604, y: -39, width: 520, height: 1010), inside: screen)
        #expect(placed.minY == 74)
        #expect(placed.maxY == 1084)
        #expect(placed.size == CGSize(width: 520, height: 1010))
    }

    @Test("a window already inside the display is left where it is")
    func aWindowThatFitsIsNotMoved() {
        let frame = CGRect(x: 604, y: 200, width: 520, height: 648)
        #expect(SettingsWindowFit.placed(frame, inside: screen) == frame)
    }

    @Test("a window taller than the display keeps its top on screen")
    func anOversizeWindowKeepsItsTitleBar() {
        let placed = SettingsWindowFit.placed(
            CGRect(x: 604, y: 0, width: 520, height: 1200), inside: screen)
        #expect(placed.maxY == 1084)
    }

    @Test("a tab switch never grows past the clamped target")
    func growingStopsAtTheTarget() {
        let target = fit(1010)
        let grown = SettingsWindowFit.grown(current: CGSize(width: 520, height: 400), toward: target)
        #expect(grown.height == target.height)
        #expect(grown.height < 1010)
    }
}
