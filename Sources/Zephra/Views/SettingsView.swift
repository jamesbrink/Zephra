import SwiftUI
import ZephraEngine

/// Preferences, in four tabs: where images land and how a run behaves, what the engine does
/// after it loads, what the models occupy on disk, and who wrote the code Zephra stands on.
///
/// The window follows the tab: each `SettingsTab` says how tall it stands, and the frame
/// changes with the selection, so General is a short window and Performance a tall one, the
/// way System Settings' own panes each take their own height. The scene's
/// `.windowResizability(.contentSize)` is what lets the window shrink as well as grow.
///
/// Escape does nothing here on purpose. On the Mac it dismisses sheets and dialogs, not
/// windows — System Settings does not close on it — and ⌘W already does; a second
/// `.cancelAction` on the window would also have competed with the Models tab's own
/// confirmation dialog whenever that was up.
struct SettingsView: View {
    @State private var tab: SettingsTab = .general

    var body: some View {
        TabView(selection: $tab) {
            ForEach(SettingsTab.allCases) { tab in
                content(of: tab)
                    .tabItem { Label(tab.title, systemImage: tab.systemImage) }
                    .tag(tab)
            }
        }
        .frame(width: 480, height: tab.height)
    }

    @ViewBuilder
    private func content(of tab: SettingsTab) -> some View {
        switch tab {
        case .general: GeneralSettings()
        case .performance: PerformanceSettings()
        case .models: ModelsSettings()
        case .about: AboutSettings()
        }
    }
}

#Preview("Settings") {
    SettingsView()
        .environment(GenerationStore.preview(state: .ready))
        .environment(ModelInventory())
        .environment(LibraryIndex(library: .pictures()))
}
