import SwiftUI
import ZephraLinkClient

/// Where the connection to the Mac has got to, in one line, plus the one piece of advice that
/// is worth giving unasked.
///
/// A phone that is looking and looking and finding nothing is usually a phone that was told no
/// when iOS asked about the local network — the browse simply returns nothing, with no error
/// and no second prompt, so nothing else in the app can say it. A few seconds of `searching`
/// is the only evidence there is, so that is what the footer is hung on.
struct ConnectionRow: View {
    /// How long a search has to run before the local network is worth mentioning.
    static let patience: Duration = .seconds(5)

    @Environment(LinkClient.self) private var client
    /// Whether the search has gone on long enough to be worth explaining.
    @State private var isSlow = false

    var body: some View {
        LabeledContent("Connection", value: Self.words(for: client.connection))
            .task(id: client.connection) { await watchForASlowSearch() }
        if isSlow, case .searching = client.connection {
            Text(
                "If this goes on, check that Zephra is allowed on the local network in "
                    + "Settings > Privacy & Security > Local Network."
            )
            .font(.footnote)
            .foregroundStyle(.secondary)
        }
    }

    /// One line for one state.
    ///
    /// A failure says the Mac's own sentence, or the client's: both were written for a person
    /// to read, and a word of our own here would only be a worse version of one of them.
    static func words(for state: LinkConnectionState) -> String {
        switch state {
        case .offline: "Offline"
        case .searching: "Searching"
        case .connecting, .handshaking: "Connecting"
        case .live(.lan): "Live on local network"
        case .live(.relay): "Live through relay"
        case .failed(let reason): reason
        }
    }

    /// Starts the clock whenever a search begins, and stops it the moment the state moves.
    private func watchForASlowSearch() async {
        isSlow = false
        guard case .searching = client.connection else { return }
        try? await Task.sleep(for: Self.patience)
        isSlow = !Task.isCancelled
    }
}

#Preview("Connection") {
    Form { ConnectionRow() }
        .environment(MobilePreview.client() ?? MobilePreview.unpairedClient())
}
