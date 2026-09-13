import SwiftUI
import ZephraLinkProtocol

struct LibrarySourcePicker: View {
    @Environment(HostConnections.self) private var hosts
    @Environment(LibraryCatalog.self) private var catalog
    var body: some View {
        Menu {
            Button { catalog.sourceFilters = [] } label: {
                Label("All Macs", systemImage: catalog.sourceFilters.isEmpty ? "checkmark" : "desktopcomputer")
            }
            ForEach(hosts.hosts) { host in
                Toggle(host.name, isOn: Binding(
                    get: { catalog.sourceFilters.contains(host.id) },
                    set: { enabled in
                        if enabled { catalog.sourceFilters.insert(host.id) }
                        else { catalog.sourceFilters.remove(host.id) }
                    }))
            }
        } label: {
            Label(title, systemImage: "line.3.horizontal.decrease")
        }
        .accessibilityLabel("Library Source, \(title)")
    }
    private var title: String {
        if catalog.sourceFilters.isEmpty { return "All Macs" }
        if catalog.sourceFilters.count == 1 {
            return hosts.hosts.first { catalog.sourceFilters.contains($0.id) }?.name ?? "Mac unavailable"
        }
        return "\(catalog.sourceFilters.count) Macs"
    }
}
