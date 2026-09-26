import SwiftUI
import ZephraLinkProtocol
import ZephraCore

struct HostQueueControls: View {
    let host: HostConnection
    @State private var failure: String?
    @State private var confirming = false
    var body: some View {
        if !(host.client.snapshot?.queue.isEmpty ?? true) {
            HStack {
                Menu("Sort Queue", systemImage: "arrow.up.arrow.down") {
                    Button("Oldest Request First") { sort(false) }
                    Button("Newest Request First") { sort(true) }
                }.disabled(!host.client.supportsWorkflow)
                Spacer()
                Button("Clear Queue", role: .destructive) { confirming = true }
            }
            .buttonStyle(.borderless)
            .disabled(!host.client.connection.isLive)
            .confirmationDialog("Clear queued jobs on \(host.name)?", isPresented: $confirming, titleVisibility: .visible) {
                Button("Clear Queue", role: .destructive) { ask { _ = try await host.client.request(.clearQueue) } }
            } message: { Text("The running job keeps going.") }
            if let failure { Text(failure).font(.caption).foregroundStyle(.secondary) }
        }
    }
    private func sort(_ newest: Bool) {
        let entries = host.client.snapshot?.queue ?? []
        let pinned = host.client.snapshot?.running?.batchID
        ask {
            let history = try await host.client.promptHistory()
            let dates = Dictionary(uniqueKeysWithValues: history.map { ($0.id, $0.createdAt) })
            var seen = Set<UUID>()
            let order = entries.compactMap { seen.insert($0.batchID).inserted ? $0.batchID : nil }
            var sorted = QueueOrder.chronological(order, dates: dates, newest: newest)
            if let pinned, sorted.contains(pinned) { sorted.removeAll { $0 == pinned }; sorted.insert(pinned, at: 0) }
            _ = try await host.client.workflow(.reorder(id: UUID(), batches: sorted, entries: entries.map(\.id)))
        }
    }
    private func ask(_ work: @escaping () async throws -> Void) {
        failure = nil
        Task { do { try await work() } catch { failure = error.localizedDescription } }
    }
}
