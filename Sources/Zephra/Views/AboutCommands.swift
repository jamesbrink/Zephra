import SwiftUI

/// The application menu's About item, pointed at `AboutPanel` so the standard panel carries
/// the third-party notices as its credits rather than opening empty.
///
/// A `Commands` of its own rather than a group inside `ZephraCommands`: that one is about
/// what the window is showing, and this is about the app.
struct AboutCommands: Commands {
    var body: some Commands {
        CommandGroup(replacing: .appInfo) {
            Button("About Zephra") { AboutPanel.show() }
        }
    }
}
