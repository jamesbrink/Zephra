import Foundation
import Testing

@testable import Zephra

/// A clicked notification and the closure that answers it arrive in either order, and the order
/// that matters is the one a cold launch takes: the delegate is set in
/// `applicationDidFinishLaunching` and the system hands the click over at once, while
/// `onNoticeOpened` is assigned from the root view's `.task`, later. A banner left in
/// Notification Center overnight and clicked with Zephra not running is exactly that case, and
/// it is the case the destination exists for.
///
/// No window and no notification centre here: `deliver` and the closure are the whole seam.
@MainActor
@Suite("What a clicked notification's destination waits for")
struct AppLifecycleNoticeTests {
    /// What the composition root's closure was handed, since a test may not capture a mutable
    /// local in a closure the app stores.
    @MainActor
    private final class Opened {
        var destinations: [NoticeDestination] = []
    }

    private func lifecycle(recording opened: Opened) -> AppLifecycle {
        let lifecycle = AppLifecycle()
        lifecycle.onNoticeOpened = { opened.destinations.append($0) }
        return lifecycle
    }

    @Test("a destination handed over with somebody to answer it goes straight there")
    func aLiveDestinationIsDeliveredAtOnce() {
        let opened = Opened()
        let lifecycle = lifecycle(recording: opened)
        lifecycle.deliver(.library(fileName: "a-picture.png"))
        #expect(opened.destinations == [.library(fileName: "a-picture.png")])
    }

    @Test("a destination that lands before the root view is held until the answer arrives")
    func aColdLaunchKeepsItsDestination() {
        let opened = Opened()
        let lifecycle = AppLifecycle()
        lifecycle.deliver(.library(fileName: "overnight.png"))
        #expect(opened.destinations.isEmpty, "nothing can be answered yet")
        lifecycle.onNoticeOpened = { opened.destinations.append($0) }
        #expect(opened.destinations == [.library(fileName: "overnight.png")])
    }

    @Test("a held destination is handed over once, not again on the next assignment")
    func aHeldDestinationIsDeliveredOnlyOnce() {
        let opened = Opened()
        let lifecycle = AppLifecycle()
        lifecycle.deliver(.library(fileName: "overnight.png"))
        lifecycle.onNoticeOpened = { opened.destinations.append($0) }
        lifecycle.onNoticeOpened = { opened.destinations.append($0) }
        #expect(opened.destinations.count == 1)
    }

    @Test("nothing waiting means nothing is delivered when the answer lands")
    func anOrdinaryLaunchDeliversNothing() {
        let opened = Opened()
        _ = lifecycle(recording: opened)
        #expect(opened.destinations.isEmpty)
    }
}
