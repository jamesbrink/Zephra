import SwiftUI
import ZephraLinkProtocol

struct ModelDownloadActions: View {
    let host: HostConnection
    let model: ModelSummary
    @State private var action = ModelActionPresentation()
    private var transfer: DownloadDTO? { host.client.snapshot?.downloads.first { $0.modelID == model.id } }
    var body: some View {
        if host.client.supportsWorkflow {
            VStack(alignment: .leading, spacing: 8) {
                if let transfer {
                    if transfer.status == .downloading {
                        ProgressView(value: transfer.fraction ?? 0)
                        Text("Downloading \(Int((transfer.fraction ?? 0) * 100))%")
                    } else if transfer.status != .completed && transfer.status != .cancelled {
                        Text(transfer.status.rawValue.capitalized).font(.caption)
                    }
                    if let message = transfer.message { Text(message).font(.caption).foregroundStyle(.secondary) }
                }
                HStack {
                    if transfer?.status == .downloading || transfer?.status == .queued {
                        Button("Pause") { ask(.pause(model.id)) }
                        Button("Cancel Download", role: .destructive) { action.confirming = true }
                    } else if transfer?.status == .paused || transfer?.status == .failed {
                        Button(transfer?.status == .failed ? "Retry Download" : "Resume Download") { ask(.download(model.id)) }
                        Button("Cancel Download", role: .destructive) { action.confirming = true }
                    } else if host.client.snapshot?.availability[model.id]?.needsNetwork == true {
                        Button("Download Only", systemImage: "arrow.down.circle") { ask(.download(model.id)) }
                    }
                }.disabled(!host.client.connection.isLive || !(host.client.snapshot?.acceptsWork ?? false) || action.busy)
                if action.busy { ProgressView("Asking \(host.name)…") }
                if let failure = action.failure { Text(failure).font(.caption).foregroundStyle(.secondary) }
            }
            .confirmationDialog("Cancel download on \(host.name)?", isPresented: $action.confirming, titleVisibility: .visible) {
                Button("Discard Unfinished Files", role: .destructive) { ask(.cancel(model.id)) }
            } message: { Text("Completed models stay. Unfinished files are discarded after their last owner releases them. Pause keeps progress for later.") }
        }
    }
    private func ask(_ command: WorkflowCommand) {
        action.ask { _ = try await host.client.workflow(command) }
    }
}
