import Testing

@testable import ZephraMobile

/// The viewer's close button has to survive a thumb, not just a cursor: a near miss on a
/// small glyph toggled the chrome instead, which took the button away underneath the finger
/// that just missed it. This pins the button at a fingertip's width rather than the glyph's.
@Suite("The viewer's close button is a fingertip wide")
struct ViewerChromeTests {
    @Test("The close button's target is at least Apple's 44-pt minimum")
    func closeButtonMeetsTheMinimumTarget() {
        #expect(LibraryViewerTitle.closeTarget >= 44)
    }
}
