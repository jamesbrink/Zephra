import SwiftUI

/// The Mac this phone is paired to, and what can be done about it. A placeholder for now:
/// unpairing, the model picker and the notification switches come next.
struct SettingsScreen: View {
    @Environment(MobileSession.self) private var session

    var body: some View {
        SurfacePlaceholder(
            title: MobileTab.settings.title, symbol: MobileTab.settings.symbol, fact: fact)
    }

    /// Which Mac, and whether it is answering right now. A paired Mac that is asleep is still
    /// paired, so the two facts are said separately rather than rolled into one word.
    private var fact: String? {
        guard let host = session.pairedHostName else { return nil }
        return session.isLive ? "Connected to \(host)" : "\(host) is not answering"
    }
}
