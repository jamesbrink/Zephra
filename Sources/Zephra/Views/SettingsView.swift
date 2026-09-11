import SwiftUI
import ZephraEngine

/// Preferences, in four tabs: where images land and how a run behaves, what the engine does
/// after it loads, what the models occupy on disk, and which phones may reach this Mac. Who wrote the code Zephra stands on is
/// the About window's Acknowledgments button, not a tab here — a fourth tab once showed the
/// same facts the About window shows, and a Settings tab duplicating a window that already
/// exists is not what any other Mac app does, so it was removed.
///
/// The window follows the tab: each `SettingsTab` says how tall it opens, and the frame
/// changes with the selection, so General is a short window and Performance a tall one, the
/// way System Settings' own panes each take their own height.
///
/// That height is an opening size rather than a fixed one, and not the window's floor either —
/// `SettingsTab.minimumHeight` is, one number for all four tabs rather than each tab's own,
/// because Performance's 820 does not fit the smallest Mac Sequoia still runs on (see that
/// type's comment for the arithmetic). The window resizes, and a person who has made it larger
/// keeps that size when they step between tabs. `SettingsWindowFrame` is what opens it at the
/// tab's size — the scene modifiers cannot, for the reasons written there — and the `.frame`
/// here only sets the floor, so a tab is laid out at its own width whatever the window is doing.
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
        // Flexible in both axes, or SwiftUI reads the tab as a fixed-size pane and takes the
        // resizable flag off the window for it — which is what the Models tab did, alone among
        // the three, however often the flag was put back.
        .frame(
            minWidth: SettingsTab.openingWidth, maxWidth: .infinity,
            minHeight: SettingsTab.minimumHeight, maxHeight: .infinity)
        .background(SettingsWindowFrame(size: tab.openingSize))
    }

    @ViewBuilder
    private func content(of tab: SettingsTab) -> some View {
        switch tab {
        case .general: GeneralSettings()
        case .performance: PerformanceSettings()
        case .models: ModelsSettings()
        case .companion: CompanionSettings()
        }
    }
}

#Preview("Settings") {
    SettingsView()
        .environment(GenerationStore.preview(state: .ready))
        .environment(ModelInventory())
        .environment(LibraryIndex(library: .pictures()))
}
