import Foundation
import Testing

@testable import Zephra

@Suite("What Quit answers while something is in flight")
struct QuitReplyTests {
    @Test("with nothing in flight and nothing to shut down, the app quits at once")
    func nothingInFlight() {
        let reply = QuitReply.for(isInstalling: false, canShutDown: false, alreadyStopping: false)
        #expect(reply == .now)
        #expect(!reply.isDeferred)
    }

    @Test("the store and the index are given their moment, as they always were")
    func theShutdownIsWaitedFor() {
        let reply = QuitReply.for(isInstalling: false, canShutDown: true, alreadyStopping: false)
        #expect(reply == .deferToShutdown)
        #expect(reply.isDeferred)
    }

    @Test("an update being swapped in holds the quit open, shutdown or no shutdown")
    func anInstallHoldsTheQuit() {
        // The window between the rename and the end of ditto: quitting in it leaves the Mac
        // with only Zephra.previous.app.
        #expect(QuitReply.for(isInstalling: true, canShutDown: true, alreadyStopping: false) == .deferToInstall)
        #expect(QuitReply.for(isInstalling: true, canShutDown: false, alreadyStopping: false) == .deferToInstall)
    }

    @Test("a quit already being honoured is answered the same way and starts nothing new")
    func asecondQuitChangesNothing() {
        for installing in [true, false] {
            for canShutDown in [true, false] {
                #expect(
                    QuitReply.for(isInstalling: installing, canShutDown: canShutDown, alreadyStopping: true)
                        == .alreadyDeferred)
            }
        }
        #expect(QuitReply.alreadyDeferred.isDeferred)
    }
}
