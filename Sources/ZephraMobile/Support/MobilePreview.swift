import Foundation

/// Launches the phone app frozen in one state, with no Mac on the other end of the wire, so a
/// surface can be photographed and inspected on its own.
///
/// Set `ZEPHRA_PREVIEW_STATE` to `pairing`, `ready`, `generating`, `library`, `offline` or
/// `settings` before launching. Debug builds only; in Release this is inert, exactly as
/// `InterfacePreview` is on the Mac — the two mechanisms are deliberately the same shape, so a
/// screenshot of either app is taken the same way.
///
/// This half is what the composition root calls. `MobilePreview+Fixtures.swift` is where the
/// state on screen comes from.
enum MobilePreview {
    /// The state asked for, or nil for an ordinary launch.
    ///
    /// Read once, here and nowhere else: nothing below the root reads the environment, so
    /// changing the variable after launch changes nothing.
    static let state: MobilePreviewState? = {
        #if DEBUG
        guard let name = ProcessInfo.processInfo.environment["ZEPHRA_PREVIEW_STATE"] else {
            return nil
        }
        return MobilePreviewState(rawValue: name)
        #else
        return nil
        #endif
    }()

    /// A session frozen in the requested state, or nil for an ordinary launch.
    ///
    /// Its `onPair` does nothing, which is what makes the frozen pairing screen safe to leave
    /// running: a code scanned into it goes nowhere.
    static func session() -> MobileSession? {
        guard let state else { return nil }
        guard state != .pairing else { return MobileSession() }
        return MobileSession(
            pairedHostName: snapshot()?.hostName ?? "halcyon",
            snapshot: state == .generating ? midRun(snapshot()) : snapshot(),
            library: library(),
            isLive: state != .offline)
    }

    /// Which surface a frozen launch opens on, and the canvas for an ordinary one.
    static var tab: MobileTab { state?.tab ?? .canvas }
}
