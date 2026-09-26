import SwiftUI

struct ModelManagementLinks: View {
    @Environment(GenerationDispatch.self) private var dispatch
    var body: some View {
        Section("Manage Models") {
            ForEach(dispatch.hosts.hosts.filter { $0.preference.enabled }) { host in
                NavigationLink("Models on " + host.name, destination: ModelManagementScreen(host: host))
            }
        }
    }
}
