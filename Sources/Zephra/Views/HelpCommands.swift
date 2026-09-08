import SwiftUI

/// The Help menu.
///
/// Replaced rather than added to, because the item AppKit synthesizes there is "Zephra Help"
/// pointing at a help book this app does not ship: choosing it opens Help Viewer on an error.
/// A menu item that cannot work is worse than no menu item, so the two things there actually
/// are to read take its place — what Zephra is, on the website, and whose work it is built on.
///
/// A `Commands` of its own rather than a group inside `ZephraCommands`, for the reason
/// `AboutCommands` is one: that one is about what the window is showing, and this is about the
/// app.
struct HelpCommands: Commands {
    @Environment(\.openURL) private var openURL
    @Environment(\.openWindow) private var openWindow

    var body: some Commands {
        CommandGroup(replacing: .help) {
            // Keeps the name AppKit's own item carries, since that is what a person looks for
            // in this menu; it simply leads somewhere that exists.
            Button("\(AppFacts.name) Help") { openURL(AppFacts.website) }
            Button("Acknowledgments") { openWindow(id: AboutScenes.acknowledgmentsID) }
        }
    }
}
