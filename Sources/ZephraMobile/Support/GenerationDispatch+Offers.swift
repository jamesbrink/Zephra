import Foundation
import ZephraLinkClient
import ZephraLinkProtocol

extension GenerationDispatch {
    func refresh(_ generation: StrictGeneration, forSubmission: Bool = false) async {
        guard !isSending || forSubmission else { return }
        if let preview = MobilePreview.offers(for: hosts) {
            offers = preview
            received = Dictionary(uniqueKeysWithValues: preview.keys.map { ($0, .now) })
            recommended = HostSelection.best(candidates())?.id
            return
        }
        let ticket = UUID(); refreshID = ticket
        var updated: [HostID: HostOffer] = [:]
        // At most eight hosts; each offer is lightweight, side-effect-free and independent.
        await withTaskGroup(of: (HostID, HostOffer?).self) { group in
            for host in hosts.hosts where host.preference.enabled && host.client.connection.isLive
                && (destination == host.id || (destination == nil && host.preference.allowsAuto)) {
                let id = host.id
                let client = host.client
                group.addTask { (id, try? await client.offer(generation)) }
            }
            for await (id, offer) in group {
                guard ticket == refreshID, !Task.isCancelled else { group.cancelAll(); return }
                if let offer {
                    updated[id] = offer
                    offers[id] = offer
                    received[id] = .now
                } else {
                    offers[id] = nil
                    received[id] = nil
                }
                recommended = HostSelection.best(candidates(), previous: recommended)?.id
            }
        }
        guard ticket == refreshID, !Task.isCancelled else { return }
        offers = updated
        recommended = HostSelection.best(candidates(), previous: recommended)?.id
    }
    func candidates() -> [HostCandidate] {
        offers.compactMap { id, offer in
            guard let host = hosts.hosts.first(where: { $0.id == id }), host.preference.enabled,
                  host.preference.allowsAuto, host.client.connection.isLive, let time = received[id] else { return nil }
            let age = time.duration(to: .now)
            let reflected = Set((host.client.snapshot?.queue.map(\.batchID) ?? [])
                + (host.client.snapshot?.running.map { [$0.batchID] } ?? []))
            let pending = submissions.filter { item in
                item.hostID == id && (item.state == .sending || item.state == .unknown
                    || (item.state == .accepted && !reflected.contains(item.batchID ?? item.id)))
            }.count
            return .init(id: id, offer: offer, age: Double(age.components.seconds) + Double(age.components.attoseconds) / 1e18,
                pendingSeconds: Double(pending) * (offer.executionSeconds ?? 60))
        }
    }
}
