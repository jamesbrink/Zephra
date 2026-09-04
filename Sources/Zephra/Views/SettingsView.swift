import AppKit
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
        // A hidden default-action-shortcut button rather than `.onExitCommand`: the exit command
        // only fires when the responder chain has nothing else to hand it to, and a `TabView`'s
        // tab controls (and any focused field within a tab) intercept Escape well before it gets
        // there. `.cancelAction` is AppKit's own Escape route — the same one `NSPanel`'s Cancel
        // button uses — and reaches the window from any focus state because it does not depend
        // on being first responder itself.
        .background {
            Button("") { NSApp.keyWindow?.close() }
                .keyboardShortcut(.cancelAction)
                .hidden()
        }
    }
}

#Preview("Settings") {
    SettingsView()
        .environment(GenerationStore.preview(state: .ready))
        .environment(ModelInventory())
}
