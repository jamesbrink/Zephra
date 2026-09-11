import SwiftUI
import UIKit
import ZephraLinkClient
import ZephraLinkProtocol
import ZephraLinkTransport

/// The composition root of the phone app: the one place that builds what the whole app
/// observes, the one place that knows how a Mac is actually reached, and the one place that
/// says when to reach for it.
///
/// One `WindowGroup` with one scene, because a phone has one. Everything a screen needs is the
/// client below, injected once; nothing under here reads the environment or opens a socket of
/// its own, exactly as `ZephraApp` is the only file on the Mac that names a backend.
@main
struct ZephraMobileApp: App {
    /// The one object every view observes. Frozen from the fixture under
    /// `ZEPHRA_PREVIEW_STATE`, and otherwise a real client over the real roads.
    @State private var client: LinkClient
    /// What keeps that client connected while the app is in front of somebody, or nil for a
    /// frozen one: a client with no road under it has nothing to reconnect.
    @State private var reconnect: LinkReconnect?
    /// The capsule's own state: what the next press of Generate would ask for.
    @State private var draft = PromptDraft()
    /// The Mac's library as this phone holds it, and "use that one as the reference" on its way
    /// from the library to the capsule. Both are facts about this phone rather than facts that
    /// came over the link, which is why they are objects of their own beside the client.
    @State private var catalog = LibraryCatalog()
    @State private var reference = ReferenceIntent()
    @Environment(\.scenePhase) private var scenePhase

    init() {
        if let frozen = MobilePreview.client() {
            _client = State(initialValue: frozen)
            _reconnect = State(initialValue: nil)
            return
        }
        let live = Self.makeClient()
        _client = State(initialValue: live)
        _reconnect = State(initialValue: LinkReconnect(client: live))
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(client)
                // What the next press of Generate will ask for. Built once and injected, so a
                // prompt survives a walk to the library and back; it holds no fact that came
                // over the link, which is the client's alone.
                .environment(draft)
                .environment(catalog)
                .environment(reference)
                // The catalog reads what is on disk and then follows the client for the life
                // of the app. Idempotent, so a scene rebuilt behind it starts nothing twice.
                .task { catalog.start(client: client) }
                // Connect while the app is in front and let the session go when it is not:
                // a phone in a pocket has no reason to hold a socket open, and the Mac has no
                // reason to hold a session for it. `initial` covers the launch itself, which
                // is an arrival at `.active` that no change of phase reports.
                .onChange(of: scenePhase, initial: true) { _, phase in
                    switch phase {
                    case .active: reconnect?.begin()
                    case .background: reconnect?.end()
                    default: break
                    }
                }
        }
    }

    /// The client an ordinary launch gets: this phone's identity and its pairing in the
    /// keychain, Bonjour and TCP on the local network with the relay behind them, and the name
    /// of the phone, which is what the Mac shows while somebody decides whether to let it in.
    private static func makeClient() -> LinkClient {
        let store = MobileKeychain()
        let identity = deviceIdentity(in: store)
        return LinkClient(
            store: store,
            roads: NetworkLinkRoads(relayURL: relayURL, identity: identity),
            deviceName: UIDevice.current.name)
    }

    /// Who this phone is, made the first time it is asked for and kept for good.
    ///
    /// Resolved here rather than left to `LinkClient`, which would do the same thing, because
    /// the roads need it too: the relay is joined with a signature over its challenge, and a
    /// second identity would be a second device as far as every paired Mac is concerned.
    private static func deviceIdentity(in store: MobileKeychain) -> DeviceIdentity {
        if let existing = try? store.loadIdentity() { return existing }
        let fresh = DeviceIdentity()
        try? store.save(fresh)
        return fresh
    }

    /// The relay, for a phone that is not on the Mac's network. A hop through somebody else's
    /// machine and the last road tried, never the first.
    private static let relayURL = URL(string: "wss://zephra-link.urandom.io")!
}
