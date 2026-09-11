import Foundation
import ZephraLinkProtocol

/// The roads a phone reaches this Mac on, built in one place so the host is handed listeners
/// and never learns what a socket is.
///
/// Two of them, eventually: a TCP listener on the local network, advertised over Bonjour, and a
/// relay road for a phone that is somewhere else. Both are `LinkListener`s, and a session does
/// not know or care which one carried it — the handshake and the channel are the same either
/// way, and the relay is a pipe that never sees inside a frame.
///
/// Empty for now. The listeners live in `ZephraLinkTransport`, which is being written beside
/// this; the wiring above is against `any LinkListener` so landing them is one line each here
/// and nothing anywhere else.
@MainActor
enum CompanionRoads {
    /// Every road this launch should listen on.
    ///
    /// - Parameters:
    ///   - relay: the relay's URL when the person has allowed access from outside the home
    ///     network, and nil when they have not.
    static func open(relay: URL?) -> [any LinkListener] {
        // TODO: `TCPListener(port: CompanionEndpoints.port)` from `ZephraLinkTransport`, a
        // `LinkListener` advertising `_zephra._tcp`, plus its relay counterpart over `relay`.
        // Until they land there is no road, so the host serves nothing and no phone can knock.
        _ = relay
        return []
    }
}
