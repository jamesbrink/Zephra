import SwiftUI
import ZephraLinkClient

/// The four surfaces, with the pairing screen over them until a Mac has been paired.
///
/// A cover rather than a branch, so the tabs are built once and keep their state: pairing is
/// something that happens in front of the app, not a different app.
struct RootView: View {
    @Environment(HostConnections.self) private var hosts
    /// Which surface is up. It lives beside the client rather than in a `@State` here, because
    /// the library's "Use as Reference" moves it and cannot reach a state of this view's.
    @Environment(MobileSelection.self) private var selection
    /// What went wrong with a link opened while a Mac was already paired.
    @State private var failure: String?

    var body: some View {
        @Bindable var selection = selection
        // A read for its own sake, and load-bearing. `TabView` reads its selection binding
        // inside itself, after this body has finished, while observation tracks only what the
        // body itself touched — so without this the tab moves when somebody taps one and never
        // when the library sends them to the canvas with a picture.
        _ = selection.tab
        return TabView(selection: $selection.tab) {
            ForEach(MobileTab.allCases) { surface in
                screen(surface)
                    .tabItem { Label(surface.title, systemImage: surface.symbol) }
                    .tag(surface)
            }
        }
        .fullScreenCover(isPresented: coverIsUp) { PairingView() }
        // Only once a Mac is paired: while the pairing screen is up it owns the link, so a
        // code that arrives as one is read and reported where the person is looking.
        .onOpenURL { url in
            guard !hosts.hosts.isEmpty else { return }
            repair(with: url.absoluteString)
        }
        .alert("That code could not be used", isPresented: alertIsUp) {
            Button("OK", role: .cancel) { failure = nil }
        } message: {
            Text(failure ?? "")
        }
    }

    /// The surface for one tab.
    @ViewBuilder private func screen(_ surface: MobileTab) -> some View {
        switch surface {
        case .canvas: CanvasScreen()
        case .today: CombinedToday()
        case .library: LibraryScreen()
        case .settings: SettingsScreen()
        }
    }

    /// Whether the pairing screen is up. Nothing but pairing takes it down, so the setter is
    /// deliberately empty: a swipe cannot dismiss a `fullScreenCover`, and no button here does.
    private var coverIsUp: Binding<Bool> {
        Binding(get: { hosts.hosts.isEmpty || hosts.isAdding }, set: { _ in })
    }

    /// Whether the failure alert is up, which is exactly whether there is a failure.
    private var alertIsUp: Binding<Bool> {
        Binding(get: { failure != nil }, set: { if !$0 { failure = nil } })
    }

    /// Pairs to another Mac from a link, the same way the pairing screen does.
    private func repair(with text: String) {
        do {
            let payload = try PairingEntry.parse(text)
            Task {
                do { try await hosts.pair(payload) } catch {
                    failure = PairingEntry.message(for: error, connection: hosts.pairing.connection)
                }
            }
        } catch {
            failure = PairingEntry.message(for: error)
        }
    }
}
