import SwiftUI
import ZephraLinkClient

/// What the pairing is doing, for as long as it is doing it.
///
/// A code read by the camera used to be followed by nothing on screen until the Mac answered
/// or every road had failed, which away from home was most of a minute at a viewfinder. The
/// client's `connection` already says which road it is on; this is that, in words, with a
/// spinner beside it, shown for exactly as long as the client is busy.
struct PairingProgress: View {
    @Environment(LinkClient.self) private var client

    var body: some View {
        if let words = Self.words(for: client.connection) {
            HStack(spacing: 8) {
                ProgressView()
                    .controlSize(.small)
                Text(words)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, MobileChrome.sideMargin)
        }
    }

    /// The line for a state, or nil for a state that is nothing to wait on.
    ///
    /// A wait is one of those. `waiting` belongs to a phone that is already paired and is
    /// being reconnected to its Mac by `LinkReconnect`; a phone on this screen is not paired
    /// with anybody, so a spinner here would be about a Mac it no longer has.
    static func words(for state: LinkConnectionState) -> String? {
        switch state {
        case .searching: "Looking for your Mac nearby…"
        case .connecting(.lan): "Connecting over the local network…"
        case .connecting(.relay): "Reaching your Mac through the secure relay…"
        case .handshaking: "Pairing…"
        case .live: "Paired"
        case .offline, .failed, .waiting: nil
        }
    }
}
