import SwiftUI
import ZephraLinkClient

/// The line under the capsule that says why nothing it shows is moving.
///
/// Two sentences and one rule between them: a phone that is about to dial again says so, and a
/// phone that is not says the numbers on screen are the last ones the Mac gave it. The
/// difference matters at the moment somebody presses Generate and nothing happens — "offline"
/// invites them to go and look at the Mac, and "reconnecting" invites them to wait a second,
/// which is usually the right thing to do.
struct ConnectionNote: View {
    /// Where the connection has got to.
    let state: LinkConnectionState

    var body: some View {
        if let words = Self.words(for: state) {
            Label(words, systemImage: Self.symbol(for: state))
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 14)
        }
    }

    /// What to say for a state, or nil for a live one, which needs nothing said about it.
    static func words(for state: LinkConnectionState) -> String? {
        switch state {
        case .live: nil
        case .waiting, .searching, .connecting, .handshaking: "Reconnecting to your Mac."
        case .offline, .failed: "Offline. This is the last thing your Mac said."
        }
    }

    /// The symbol beside those words.
    private static func symbol(for state: LinkConnectionState) -> String {
        switch state {
        case .waiting, .searching, .connecting, .handshaking: "arrow.clockwise"
        case .live, .offline, .failed: "wifi.slash"
        }
    }
}

#Preview("Reconnecting") {
    ConnectionNote(state: .waiting(reason: "Zephra could not reach halcyon.", until: Date()))
}
