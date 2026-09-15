/// The states a Debug build of the phone app can be frozen in, for screenshots and for
/// looking at a surface without a Mac on the other end of the wire.
///
/// The Mac's list is longer because the Mac has an engine to freeze; here there are only two
/// axes — which surface is up, and whether the wire is live — so six states cover the app.
enum MobilePreviewState: String, CaseIterable {
    /// No Mac paired: the pairing screen, over nothing.
    case pairing
    /// Paired and idle, on the canvas.
    case ready
    /// Paired, on the canvas, with a run four steps into its ladder and a frame of it in.
    case generating
    /// Paired and idle, on the canvas, with the capsule showing every control the model has.
    case capsule
    /// Paired, on the library, over the fixture's pictures.
    case library
    /// Paired, on the library, with its first picture open full size.
    case viewer
    /// Paired, on today's runs, with one running and one waiting.
    case today
    /// Paired, but the Mac is not answering: everything on screen is the last thing known.
    case offline
    /// Paired, on the canvas, with the Mac's last run lost and the way back on screen.
    case failed
    /// Paired, on the settings surface.
    case settings

    /// Which surface the frozen app opens on.
    var tab: MobileTab {
        switch self {
        case .pairing, .ready, .generating, .capsule, .offline, .failed: .canvas
        case .library, .viewer: .library
        case .today: .today
        case .settings: .settings
        }
    }
}
