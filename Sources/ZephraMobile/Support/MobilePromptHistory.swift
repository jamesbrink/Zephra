import Foundation
import Observation
import ZephraCore

@MainActor @Observable
final class MobilePromptHistory {
    var entries: [MobilePromptEntry] = []
    var failure: String?
    var showing = false
    var isLoading = false
    var recall = PromptRecall()
    private var refreshID = UUID()
    func refresh(_ dispatch: GenerationDispatch) async {
        let ticket = UUID(); refreshID = ticket
        let destination = dispatch.destination
        let hosts = dispatch.hosts.hosts.filter {
            if let destination { return $0.id == destination }
            return $0.preference.enabled && $0.client.connection.isLive
        }
        isLoading = true; failure = nil
        var collected: [MobilePromptEntry] = []
        var errors: [String] = []
        for host in hosts {
            if host.client.supportsWorkflow && host.client.connection.isLive {
                do {
                    let rows = try await host.client.promptHistory()
                    collected += rows.map { MobilePromptEntry(id: host.id.rawValue + ":" + $0.id.uuidString,
                        hostID: host.id, hostName: host.name, prompt: $0.prompt, createdAt: $0.createdAt) }
                } catch { errors.append(host.name + ": " + error.localizedDescription) }
            } else {
                // Older Macs and offline manual destinations still have saved library prompts.
                var seen = Set<String>()
                for entry in host.catalog.entries.sorted(by: { $0.createdAt > $1.createdAt }) {
                    guard !entry.prompt.isEmpty else { continue }
                    let batch = entry.entry.record?.batchID?.uuidString ?? entry.id
                    guard seen.insert(batch).inserted else { continue }
                    collected.append(MobilePromptEntry(id: host.id.rawValue + ":" + batch,
                        hostID: host.id, hostName: host.name, prompt: entry.prompt, createdAt: entry.createdAt))
                }
            }
        }
        guard ticket == refreshID, destination == dispatch.destination, !Task.isCancelled else { return }
        entries = Array(MobilePromptEntry.ordered(collected).prefix(300))
        failure = errors.isEmpty ? nil : errors.joined(separator: "\n")
        isLoading = false
    }
    func reset() { refreshID = UUID(); recall.reset(); entries = []; isLoading = false }
}
