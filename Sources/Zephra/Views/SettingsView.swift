import SwiftUI
import ZephraEngine

/// Preferences, in three tabs: where images land and how a run behaves, what the engine does
/// after it loads, and who wrote the code Zephra stands on.
struct SettingsView: View {
    var body: some View {
        TabView {
            GeneralSettings().tabItem { Label("General", systemImage: "gearshape") }
            PerformanceSettings().tabItem { Label("Performance", systemImage: "speedometer") }
            AboutSettings().tabItem { Label("About", systemImage: "info.circle") }
        }
        // Tall enough for Performance, the longest of the three; the other two centre in it.
        .frame(width: 480, height: 440)
    }
}

#Preview("Settings") {
    SettingsView()
        .environment(GenerationStore.preview(state: .ready))
}
