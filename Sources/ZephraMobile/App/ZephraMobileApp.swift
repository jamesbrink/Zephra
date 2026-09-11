import SwiftUI
import ZephraLinkProtocol

/// The composition root of the phone app: the one place that builds what the whole app
/// observes, and the one place that will know how a Mac is actually reached.
///
/// One `WindowGroup` with one scene, because a phone has one. Everything a screen needs is the
/// session below, injected once; nothing under here reads the environment or opens a socket of
/// its own, exactly as `ZephraApp` is the only file on the Mac that names a backend.
@main
struct ZephraMobileApp: App {
    /// The one object every view observes. Frozen from the fixture under
    /// `ZEPHRA_PREVIEW_STATE`, and otherwise empty and waiting to be paired.
    @State private var session = MobilePreview.session() ?? ZephraMobileApp.makeSession()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(session)
        }
    }

    /// The session an ordinary launch gets.
    ///
    /// `onPair` records the Mac and nothing else for now: the client that opens the channel,
    /// completes the handshake and starts taking deltas is being built beside this, and this
    /// is the seam it lands on. Until then the phone pairs, names the Mac and shows that
    /// nothing is answering, which is the truth.
    private static func makeSession() -> MobileSession {
        let session = MobileSession()
        session.onPair = { [weak session] payload in
            session?.pairedHostName = payload.hostName
            session?.isLive = false
        }
        return session
    }
}
