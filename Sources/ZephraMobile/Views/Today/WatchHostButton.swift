import SwiftUI

struct WatchHostButton: View {
    let host: HostConnection
    @Environment(HostConnections.self) private var hosts
    @Environment(MobileSelection.self) private var selection
    var body: some View {
        Button("Watch on \(host.name)", systemImage: "play.rectangle") {
            hosts.watch(host.id)
            selection.tab = .canvas
        }
    }
}
