import SwiftUI
import ZephraLinkProtocol

struct HostModelRow: View {
    let host: HostConnection
    let model: ModelSummary
    @State private var failure: String?
    var body: some View {
        VStack(alignment: .leading) {
            LabeledContent(model.label, value: host.client.snapshot?.availability[model.id]?.label ?? "Unknown")
            Button("Load on \(host.name)") {
                Task {
                    do { try await host.client.switchModel(model.id) }
                    catch { failure = error.localizedDescription }
                }
            }
            .disabled(!host.client.connection.isLive)
            if let failure { Text(failure).font(.caption).foregroundStyle(.secondary) }
        }
        .accessibilityHint("May download or prepare this model. Auto never starts a download.")
    }
}
