import SwiftUI
import ZephraCore
import ZephraLinkClient
import ZephraLinkProtocol

struct QueueRunActions: ViewModifier {
    let id: UUID
    @Environment(LinkClient.self) private var client
    @State private var failure: String?
    private var order: [UUID] {
        var seen = Set<UUID>()
        return (client.snapshot?.queue ?? []).compactMap { seen.insert($0.batchID).inserted ? $0.batchID : nil }
    }
    func body(content: Content) -> some View {
        content
            .draggable(id.uuidString)
            .dropDestination(for: String.self) { values, _ in
                guard client.supportsWorkflow, let source = values.first.flatMap(UUID.init(uuidString:)),
                      order.contains(source) else { return false }
                send(QueueOrder.moving(source, before: id, in: order)); return true
            }
            .contextMenu {
                Button("Move Earlier", systemImage: "arrow.up") { move(true) }.disabled(!canMove(true))
                Button("Move Later", systemImage: "arrow.down") { move(false) }.disabled(!canMove(false))
            }
            .accessibilityAction(named: "Move Earlier") { move(true) }
            .accessibilityAction(named: "Move Later") { move(false) }
            .alert("Queue Changed", isPresented: Binding(get: { failure != nil }, set: { if !$0 { failure = nil } })) {
                Button("OK") { failure = nil }
            } message: { Text(failure ?? "") }
    }
    private func canMove(_ earlier: Bool) -> Bool {
        guard client.supportsWorkflow, client.connection.isLive, let index = order.firstIndex(of: id),
              id != client.snapshot?.running?.batchID else { return false }
        let other = index + (earlier ? -1 : 1)
        return order.indices.contains(other) && order[other] != client.snapshot?.running?.batchID
    }
    private func move(_ earlier: Bool) {
        guard canMove(earlier) else { return }
        send(QueueOrder.adjacent(id, earlier: earlier, in: order))
    }
    private func send(_ batches: [UUID]) {
        let command = WorkflowCommand.reorder(id: UUID(), batches: batches, entries: client.snapshot?.queue.map(\.id) ?? [])
        Task { do { _ = try await client.workflow(command) } catch { failure = error.localizedDescription } }
    }
}
