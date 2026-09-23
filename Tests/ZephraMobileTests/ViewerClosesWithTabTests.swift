import Testing
@testable import ZephraMobile

@Suite("The viewer closes when the tab under it moves")
struct ViewerClosesWithTabTests {
    @Test("Use as Reference from the library's viewer closes it as the canvas comes up")
    func libraryToCanvas() {
        #expect(ViewerClosesWithTab.closes(openedOver: .library, now: .canvas))
    }

    @Test("a viewer opened over Today closes the same way")
    func todayToCanvas() {
        #expect(ViewerClosesWithTab.closes(openedOver: .today, now: .canvas))
    }

    @Test("a viewer over the tab it opened on stays up")
    func sameTabStays() {
        #expect(!ViewerClosesWithTab.closes(openedOver: .library, now: .library))
    }

    @Test("a viewer that has not yet appeared closes nothing")
    func notYetAppeared() {
        #expect(!ViewerClosesWithTab.closes(openedOver: nil, now: .canvas))
    }
}
