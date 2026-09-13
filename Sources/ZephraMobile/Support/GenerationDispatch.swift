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
    private(set) var submissions: [Submission] = []
    @ObservationIgnored var received: [HostID: ContinuousClock.Instant] = [:]
    @ObservationIgnored let root: URL?
    @ObservationIgnored var refreshID = UUID()
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
    var target: HostConnection? { hosts.hosts.first { $0.id == (destination ?? recommended) } }
    var reason: String {
        guard let target else { return "No eligible Mac. Check connections and model readiness." }
        if !target.preference.enabled { return "This Mac is disabled. Enable it in Settings." }
        if !target.client.connection.isLive { return "Reconnect \(target.name) to send this job." }
        if let offer = offers[target.id] { return offer.refusal ?? HostSelection.reason(offer) }
        return target.client.supportsMultiHost ? "Checking this Mac…" : "Manual destination · update this Mac to use Auto"
    }
}
