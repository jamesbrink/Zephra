import SwiftUI

struct LibraryOwnershipAccessibility: ViewModifier {
    let entry: CachedEntry
    @Environment(HostConnections.self) private var hosts
    func body(content: Content) -> some View {
        content.accessibilityLabel(entry.label + source)
    }
    private var source: String {
        guard let host = hosts.hosts.first(where: { $0.id == entry.hostID }) else { return "" }
        return ", from \(host.name)\(host.client.connection.isLive ? "" : ", offline")"
    }
}
