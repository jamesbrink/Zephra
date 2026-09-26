import Foundation
import ZephraLinkClient

/// Launches the phone app frozen in one state, with no Mac on the other end of the wire, so a
/// surface can be photographed and inspected on its own.
///
/// Set `ZEPHRA_PREVIEW_STATE` to `pairing`, `ready`, `generating`, `capsule`, `library`,
/// `viewer`, `today`, `offline`, `failed` or `settings` before launching. Debug builds only; in Release this is inert, exactly as
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

    /// A client frozen in the requested state, or nil for an ordinary launch.
    ///
    /// `LinkClient.frozen` is a client with no road under it: requests answer `.ok` and blobs
    /// fail, so a screenshot build cannot queue a generation on somebody's Mac. The pairing
    /// state is the one that is not frozen — it has no snapshot to be frozen over — and is a
    /// real client over roads that go nowhere, so a code pasted into it says it could not reach
    /// the Mac rather than doing nothing at all.
    static func client() -> LinkClient? {
        guard let state else { return nil }
        guard var snapshot = snapshot(), state != .pairing else { return unpairedClient() }
        snapshot.workflow = true
        if hostCount > 1 { snapshot.multiHost = true }
        return LinkClient.frozen(
            snapshot: shaped(snapshot, for: state),
            library: library(),
            connection: state == .offline ? .offline : .live(.lan),
            preview: state == .generating ? frame() : nil)
    }

    /// Which surface a frozen launch opens on, and the canvas for an ordinary one.
    static var tab: MobileTab { state?.tab ?? .canvas }

    /// Whether the canvas opens with its capsule showing every control, which is the only way
    /// to photograph the settings: a screenshot build cannot tap.
    static var capsuleIsExpanded: Bool { state == .capsule }

    /// A client that has never paired and has no road to anything, for the pairing state and
    /// for an Xcode canvas, which launches no process and so sets no preview state.
    static func unpairedClient() -> LinkClient {
        LinkClient(
            store: MemoryLinkKeyStore(), roads: MemoryLinkRoads.unreachable(),
            deviceName: "Preview")
    }
}
