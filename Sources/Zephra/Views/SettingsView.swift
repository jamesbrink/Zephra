import SwiftUI
import ZephraEngine

/// Preferences, in four tabs: where images land and how a run behaves, what the engine does
/// after it loads, what the models occupy on disk, and who wrote the code Zephra stands on.
struct SettingsView: View {
    var body: some View {
        TabView {
            GeneralSettings().tabItem { Label("General", systemImage: "gearshape") }
            PerformanceSettings().tabItem { Label("Performance", systemImage: "speedometer") }
            ModelsSettings().tabItem { Label("Models", systemImage: "shippingbox") }
            AboutSettings().tabItem { Label("About", systemImage: "info.circle") }
        }
        // Tall enough for Performance, the longest of the four; the others centre in it.
        .frame(width: 480, height: 620)
    }
}

#Preview("Settings") {
    SettingsView()
        .environment(GenerationStore.preview(state: .ready))
        .environment(ModelInventory())
}
