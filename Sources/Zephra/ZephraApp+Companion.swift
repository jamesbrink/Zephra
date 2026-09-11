import Foundation
import SwiftUI
import ZephraEngine
import ZephraLinkHost
import ZephraLinkProtocol

/// The composition root's other wiring: the link a paired phone talks to this Mac over.
///
/// Built once, beside the store and the index, and handed both. It is built whether or not the
/// preference is on, because Settings has to be able to show the paired devices and put a code
/// up before anything is listening; what the preference decides is whether a road is opened at
/// all. Nothing is reachable until one is.
extension ZephraApp {
    /// Builds the host and opens its roads if the person has allowed it.
    ///
    /// Silent on a frozen preview build and under the app-hosted tests: neither owns this Mac's
    /// keychain or its port, and a screenshot build listening on the network would be a surprise.
    func startCompanion() async {
        guard companion == nil, InterfacePreview.requestedState == nil else { return }
        let keychain = LinkKeychain(isFreshStart: FreshStart.current != nil)
        // Off the main actor, both reads. A keychain item whose access list no longer names
        // this copy of the app raises a system password prompt, and `SecItemCopyMatching` does
        // not return until somebody answers it — on the main thread that is the whole app
        // stopped before its first window, with nothing on screen to explain why. Read here,
        // the worst a prompt left unanswered costs is a link that has not started yet.
        let opened = await Task.detached(priority: .userInitiated) { () -> (DeviceIdentity, [PairedDevice])? in
            guard let identity = try? keychain.identity() else { return nil }
            return (identity, (try? keychain.load()) ?? [])
        }.value
        guard let (identity, devices) = opened else { return }
        roads.remember(identity)
        // The port is asked for when the code goes up, not now: the local road may have taken a
        // different one, and a code that named 7723 when the listener is elsewhere is a code
        // that does not work.
        let roads = self.roads
        let host = CompanionHost(
            store: store,
            index: index,
            thumbnails: CompanionThumbnails(folder: thumbnails.folder),
            identity: identity,
            pairings: keychain,
            hostName: AppSettings.companionName(),
            devices: devices,
            endpoints: { CompanionEndpoints.current(port: roads.port) })
        companion = host
        // The library's own wiring ran first (`openLibrary`), so these are wrapped rather than
        // replaced: a save still reaches the index and still posts its notification, and the
        // link is told as well, so a picture appears on a phone without waiting for the
        // observation loop's next pass.
        let saved = store.onImageSaved
        store.onImageSaved = { url in
            saved?(url)
            host.publishNow()
        }
        let deleted = store.onImageDeleted
        store.onImageDeleted = { url in
            deleted?(url)
            host.publishNow()
        }
        openCompanionRoads()
    }

    /// Opens or closes the roads to match the preference, which is what the Settings toggle
    /// changes. Called at launch and whenever the toggle moves.
    func openCompanionRoads() {
        guard let host = companion else { return }
        Task {
            // The host stops with the roads: a listener taken away while sessions are open on
            // it would leave phones holding a connection nothing is reading.
            await host.stop()
            await roads.close()
            guard AppSettings.flag(AppSettings.companionEnabled) else { return }
            // Weakly, because the host holds every listener it is served and the relay road
            // reads the host's paired devices: a strong closure would be a cycle.
            let opened = await roads.open(
                relay: AppSettings.companionRelay(),
                allowing: { [weak host] in host?.relayAllowList ?? [] })
            for road in opened { host.serve(road) }
        }
    }

    /// Closes every session and stops listening, before the store and the index settle.
    ///
    /// First in `shutdown` because a phone holding a request open is the one reader that could
    /// still ask the store for work while it is trying to finish, and a session closed cleanly
    /// is a phone that says so rather than one that times out.
    func stopCompanion() async {
        await companion?.stop()
        await roads.close()
    }
}
