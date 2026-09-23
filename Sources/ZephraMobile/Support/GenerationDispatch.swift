import Foundation
import Observation
import ZephraLinkClient
import ZephraLinkProtocol

/// Chooses a destination once, persists it before sending, and reconciles only with its owner.
@MainActor @Observable
final class GenerationDispatch {
    let hosts: HostConnections
    var destination: HostID?
    var offers: [HostID: HostOffer] = [:]
    var recommended: HostID?
    var note: String?
    var isSending = false
    /// The run the last press queued, while there is something to say about it.
    var following: RunFollowing?
    private(set) var submissions: [Submission] = []
    @ObservationIgnored var received: [HostID: ContinuousClock.Instant] = [:]
    @ObservationIgnored let root: URL?
    @ObservationIgnored var offerSessions: [HostID: UUID] = [:]
    @ObservationIgnored var refreshID = UUID()
    @ObservationIgnored var followTask: Task<Void, Never>?
    init(hosts: HostConnections, root: URL?) {
        self.hosts = hosts; self.root = root
        if let root, FileManager.default.fileExists(atPath: root.path) {
            do {
                let data = try Data(contentsOf: root)
                submissions = try LinkJSON.decode([Submission].self, from: data)
                for index in submissions.indices where submissions[index].state == .sending {
                    submissions[index].state = .unknown
                }
            } catch { note = "Saved submissions could not be read. Sending is unavailable."; isSending = true }
        }
    }
    func publish(_ records: [Submission]) { submissions = records }

    var models: [ModelSummary] {
        var found: [String: ModelSummary] = [:]
        for host in hosts.hosts where destination == nil || destination == host.id {
            for model in host.client.snapshot?.models ?? [] { if found[model.id] == nil { found[model.id] = model } }
        }
        return found.values.sorted { $0.label < $1.label }
    }
    var target: HostConnection? {
        let id = destination ?? HostSelection.best(candidates(), previous: recommended)?.id
        return hosts.hosts.first { $0.id == id }
    }
    /// Eligibility is the selected Mac's offer; the phone estimates no memory requirements.
    var canSend: Bool {
        guard let target, target.preference.enabled, target.client.connection.isLive,
              target.client.hasFreshSnapshot else { return false }
        if target.client.supportsMultiHost {
            guard let offer = freshOffer(for: target) else { return false }
            return offer.refusal == nil
        }
        return destination != nil
    }
    var reason: String {
        guard let target else {
            let refusals = hosts.hosts.compactMap { host -> String? in
                guard host.preference.enabled, host.preference.allowsAuto,
                      let refusal = freshOffer(for: host)?.refusal else { return nil }
                return "\(host.name): \(refusal)"
            }
            return refusals.isEmpty ? "No eligible Mac. Check connections and model readiness."
                : refusals.joined(separator: "\n")
        }
        if !target.preference.enabled { return "This Mac is disabled. Enable it in Settings." }
        if !target.client.connection.isLive { return "Reconnect \(target.name) to send this job." }
        if let offer = freshOffer(for: target) { return offer.refusal ?? HostSelection.reason(offer, selected: destination == nil ? target.id : nil, candidates: candidates()) }
        return target.client.supportsMultiHost ? "Checking this Mac…" : "Manual destination · update this Mac to use Auto"
    }
}
