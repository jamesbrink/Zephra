import SwiftUI

@main
struct ZephraMobileApp: App {
    @State private var workspace = MobileWorkspace()
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            MobileRoot(workspace: workspace)
                .modifier(AppearancePreference())
                .modifier(SeedFormatPreference())
                .defaultAppStorage(MobileSettings.store)
                .onChange(of: scenePhase, initial: true) { _, phase in
                    if phase == .active { workspace.hosts.setActive(true) }
                    if phase == .background { workspace.hosts.setActive(false) }
                }
        }
    }
}
