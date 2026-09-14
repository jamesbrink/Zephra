import Foundation
import ZephraLinkProtocol

extension GenerationDispatch {
    /// An offer belongs to the authenticated session that answered it, never its next reconnect.
    func freshOffer(for host: HostConnection) -> HostOffer? {
        guard host.client.connection.isLive, host.client.hasFreshSnapshot,
              offerSessions[host.id] == host.client.authenticatedSessionID,
              let offer = offers[host.id], offer.lifetime.isFinite, offer.lifetime > 0,
              let time = received[host.id] else { return nil }
        let age = time.duration(to: .now)
        guard age >= .zero, age <= .seconds(min(offer.lifetime, 5)) else { return nil }
        return offer
    }
}
