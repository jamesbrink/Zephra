import SwiftUI

struct MobileRoot: View {
    let workspace: MobileWorkspace
    var body: some View {
        Group {
            if let failure = workspace.startupFailure {
                ContentUnavailableView("Connections Unavailable", systemImage: "lock", description: Text(failure))
            } else {
                RootView()
                    .environment(workspace.hosts)
                    .environment(workspace.dispatch)
                    .environment(workspace.hosts.client)
                    .environment(workspace.hosts.visible?.reconnect)
                    .environment(workspace.hosts.catalog)
                    .environment(workspace.draft)
                    .environment(workspace.reference)
                    .environment(workspace.selection)
                    .task { await workspace.hosts.observe() }
                    .task {
                        while !Task.isCancelled {
                            if workspace.hosts.isActive { await workspace.dispatch.reconcile() }
                            try? await Task.sleep(for: .seconds(3))
                        }
                    }
            }
        }
    }
}
