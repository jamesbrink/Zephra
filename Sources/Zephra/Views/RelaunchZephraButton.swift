import SwiftUI

/// The one remedy for a GPU this launch has lost.
///
/// It stands where Try Again stands for every other failure, and for the reason Try Again is
/// not there: the driver refuses this process's command buffers whatever is asked of it, so a
/// retry, an unload and a switch to another model each fail in a third of a second. The press
/// is `Relaunch.thisApp()`, which is the updater's own script and run-loop quit rather than a
/// second way out of the app. A Mac left to itself relaunches without this being pressed; see
/// `DeviceLossRelaunch`.
struct RelaunchZephraButton: View {
    var body: some View {
        Button("Relaunch Zephra") { Relaunch.thisApp() }
            .buttonStyle(.bordered)
            .controlSize(.large)
            .padding(.top, 4)
            .help("Quit and open Zephra again, which is the only way to get the GPU back")
    }
}

#Preview("Relaunch") {
    RelaunchZephraButton().padding()
}
