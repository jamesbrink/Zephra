import SwiftUI

struct ModelManagementScreen: View {
    let host: HostConnection
    @State private var storage = RemoteModelStorage()
    var body: some View {
        Form {
            Section {
                Text("Downloads and model files are on \(host.name). Download Only and Resume keep the current model selected and do not load weights.")
                    .font(.callout).foregroundStyle(.secondary)
                if !host.client.connection.isLive { Text("Reconnect this Mac to manage its models.").foregroundStyle(.secondary) }
                if !host.client.supportsWorkflow { Text("Update Zephra on this Mac for download and storage controls.").foregroundStyle(.secondary) }
            }
            Section("Models on \(host.name)") {
                ForEach(host.client.snapshot?.models ?? []) { model in HostModelRow(host: host, model: model) }
            }
            if host.client.supportsWorkflow {
                Section("Model Storage") {
                    if storage.loading { ProgressView("Reading model storage…") }
                    ForEach(storage.rows) { row in RemoteModelStorageRow(item: row, host: host, storage: storage) }
                    if storage.rows.isEmpty && !storage.loading { Text("No model files found.").foregroundStyle(.secondary) }
                    Text("Total: " + storage.rows.reduce(0) { $0 + ($1.bytes ?? 0) }.formatted(.byteCount(style: .file)))
                        .font(.caption).foregroundStyle(.secondary)
                    Button("Refresh Storage", systemImage: "arrow.clockwise") { Task { await storage.refresh(host) } }
                        .disabled(storage.loading || !host.client.connection.isLive)
                    if let failure = storage.failure { Text(failure).font(.caption).foregroundStyle(.secondary) }
                }
            }
        }
        .navigationTitle("Models · " + host.name)
        .navigationBarTitleDisplayMode(.inline)
        .task { if host.client.supportsWorkflow { await storage.refresh(host) } }
        .onChange(of: host.client.snapshot?.engine.loadedModelID) {
            Task { if host.client.supportsWorkflow { await storage.refresh(host) } }
        }
        .refreshable { if host.client.supportsWorkflow { await storage.refresh(host) } }
        .alert("Permanently delete model files?", isPresented: Binding(get: { storage.deleting != nil }, set: { if !$0 { storage.deleting = nil } }), presenting: storage.deleting) { item in
            Button("Delete Permanently", role: .destructive) { Task { await storage.delete(host, item: item) } }
            Button("Cancel", role: .cancel) { storage.deleting = nil }
        } message: { item in
            Text("Delete \(item.name) on \(host.name)? This cannot be undone. \(item.modelIDs.count > 1 ? "Several models share these files. " : "")Using them again requires downloading or rebuilding them.")
        }
    }
}
