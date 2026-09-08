import SwiftUI

/// The application menu's About item, opening `AboutScenes`' About window in place of the
/// standard panel.
///
/// A `Commands` of its own rather than a group inside `ZephraCommands`: that one is about
/// what the window is showing, and this is about the app.
struct AboutCommands: Commands {
    @Environment(\.openWindow) private var openWindow

    var body: some Commands {
        CommandGroup(replacing: .appInfo) {
            Button("About \(AppFacts.name)") { openWindow(id: AboutScenes.aboutID) }
        }
    }
}
