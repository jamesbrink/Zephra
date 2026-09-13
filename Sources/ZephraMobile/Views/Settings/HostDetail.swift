import SwiftUI

struct HostDetail: View {
    let host: HostConnection
    @Environment(HostConnections.self) private var hosts
    @State private var confirming = false
    var body: some View {
        Form {
            Section("Connection") {
                TextField("Name", text: Binding(get: { host.name }, set: { value in
                    var preference = host.preference; preference.alias = value; hosts.update(preference)
                }))
                Toggle("Enabled", isOn: Binding(get: { host.preference.enabled }, set: { value in
                    var preference = host.preference; preference.enabled = value; hosts.update(preference)
                }))
                Toggle("Include in Auto", isOn: Binding(get: { host.preference.allowsAuto }, set: { value in
                    var preference = host.preference; preference.allowsAuto = value; hosts.update(preference)
                }))
                ConnectionRow().environment(host.client).environment(host.reconnect)
                Button("Watch This Mac") { hosts.watch(host.id) }
                Text("Loading a model below may download or prepare it. Auto uses models that are already ready.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("Models") {
                ForEach(host.client.snapshot?.models ?? []) { model in
                    HostModelRow(host: host, model: model)
                }
            }
            Section {
                Button("Forget Mac", role: .destructive) { confirming = true }
            }
        }
        .navigationTitle(host.name)
        .confirmationDialog("Forget \(host.name)?", isPresented: $confirming, titleVisibility: .visible) {
            Button("Forget Mac", role: .destructive) { Task { await hosts.forget(host) } }
        } message: {
            Text("This removes its pairing and cached library from this phone. Files and jobs on the Mac remain, including submissions whose status is uncertain.")
        }
    }
}
