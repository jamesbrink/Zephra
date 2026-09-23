import SwiftUI
import ZephraLinkProtocol

struct DestinationPicker: View {
    @Environment(GenerationDispatch.self) private var dispatch
    @Environment(PromptDraft.self) private var draft

    var body: some View {
        @Bindable var dispatch = dispatch
        VStack(alignment: .leading, spacing: 3) {
            Menu {
                Picker("Send To", selection: $dispatch.destination) {
                    Text("Auto").tag(Optional<HostID>.none)
                    ForEach(dispatch.hosts.hosts) { host in
                        Text(host.name + (host.client.connection.isLive ? "" : " · Offline"))
                            .tag(Optional(host.id))
                    }
                }
            } label: {
                HStack {
                    Text(destinationLabel).multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                    Image(systemName: "chevron.down").font(.caption)
                }
            }
            .accessibilityLabel("Send To, \(destinationLabel)")
            .disabled(dispatch.isSending)
            Text(dispatch.destination == nil ? "Auto · \(dispatch.target?.name ?? "No Mac available")" : dispatch.target?.name ?? "Mac unavailable")
                .font(.caption.weight(.medium))
            Text(dispatch.reason).font(.caption2).foregroundStyle(.secondary)
        }
        .padding(.horizontal, 14)
        .task(id: fingerprint) {
            while !Task.isCancelled {
                await dispatch.refresh(StrictGeneration(request: GenerationRequest(
                    modelID: draft.modelID, count: draft.count, settings: draft.settings),
                    inputs: dispatch.inputs(for: draft.references)))
                
                try? await Task.sleep(for: .seconds(3))
            }
        }
    }
    private var destinationLabel: String {
        guard dispatch.destination != nil else { return "Auto" }
        guard let host = dispatch.target else { return "Mac unavailable" }
        return host.name + (host.client.connection.isLive ? "" : " · Offline")
    }
    private var fingerprint: String {
        "\(draft.modelID)|\(draft.settings.hashValue)|\(draft.count)|\(dispatch.destination?.rawValue ?? "auto")|\(dispatch.fingerprint(of: draft.references))"
    }
}
